"""
TIFF reader for FilmCutter.

Pixel data is read with tifffile so 16-bit RGB scans are not silently
quantized to 8-bit by Pillow.
"""

import os

import numpy as np
import tifffile


def _first_value(value, default=0):
    if value is None:
        return default
    if isinstance(value, (tuple, list)):
        return value[0] if value else default
    return value


def _page_bit_depth(page) -> int:
    return int(_first_value(page.bitspersample, 8))


def _page_mode(array: np.ndarray) -> str:
    if array.ndim == 2:
        return "L"
    if array.ndim == 3 and array.shape[-1] == 4:
        return "RGBA"
    if array.ndim == 3 and array.shape[-1] >= 3:
        return "RGB"
    return "L"


def _dpi_from_page(page) -> tuple:
    try:
        xres = page.tags.get("XResolution")
        yres = page.tags.get("YResolution")
        x = float(xres.value[0]) / float(xres.value[1]) if xres else 0
        y = float(yres.value[0]) / float(yres.value[1]) if yres else 0
        return (x, y)
    except (TypeError, ValueError, ZeroDivisionError):
        return (0, 0)


def _validate_page(page, page_count: int):
    if page_count != 1:
        raise ValueError(
            f"Multi-page TIFF is not supported yet ({page_count} pages). "
            "Export or split it into one TIFF per scan."
        )
    compression = getattr(page.compression, "name", str(page.compression))
    if compression not in {"NONE", "1"}:
        raise ValueError(
            f"Compressed TIFF is not supported in FilmCutter 1.1 ({compression}). "
            "Export an uncompressed TIFF."
        )


def read_image(filepath: str, memory_mapped: bool = False) -> tuple:
    """
    Read the first page of a TIFF while preserving its native sample depth.

    When memory_mapped is true, uncompressed contiguous TIFFs are accessed
    directly from the source file. Other layouts are decoded to a temporary
    disk-backed map. This bounds export RAM to roughly one cropped frame.

    Returns:
        (image_array, metadata_dict)
    """
    if not os.path.exists(filepath):
        raise FileNotFoundError(f"File not found: {filepath}")

    ext = os.path.splitext(filepath)[1].lower()
    if ext not in (".tif", ".tiff"):
        raise ValueError(
            f"Unsupported file format: {ext}. Only .tif/.tiff files are supported."
        )

    with tifffile.TiffFile(filepath) as tif:
        if not tif.pages:
            raise ValueError("TIFF contains no image pages")
        page = tif.pages[0]
        _validate_page(page, len(tif.pages))
        if memory_mapped:
            try:
                array = tifffile.memmap(filepath, page=0, mode="r")
            except (ValueError, TypeError):
                array = page.asarray(out="memmap")
        else:
            array = page.asarray()

        # TIFF permits RGB samples to be stored as either H×W×C (contiguous)
        # or C×H×W (planar separate). The rest of FilmCutter has one canonical
        # in-memory contract, H×W×C, so normalize before detection or preview.
        samples = int(_first_value(page.samplesperpixel, 1))
        if (
            array.ndim == 3
            and samples in (3, 4)
            and array.shape[0] == samples
            and array.shape[-1] != samples
        ):
            array = np.moveaxis(array, 0, -1)

        if array.ndim == 3 and array.shape[-1] == 4:
            array = array[:, :, :3]

        if array.dtype not in (np.uint8, np.uint16):
            if np.issubdtype(array.dtype, np.integer):
                array = np.clip(array, 0, 65535).astype(np.uint16)
            else:
                raise ValueError(f"Unsupported TIFF sample type: {array.dtype}")

        compression = getattr(page.compression, "name", str(page.compression))
        resolution_unit = getattr(
            page.resolutionunit, "name", str(page.resolutionunit)
        )
        icc_tag = page.tags.get(34675)  # InterColorProfile
        icc_profile = bytes(icc_tag.value) if icc_tag is not None else None
        metadata = {
            "width": int(page.imagewidth),
            "height": int(page.imagelength),
            "mode": _page_mode(array),
            "bit_depth": _page_bit_depth(page),
            "compression": compression,
            "dpi": _dpi_from_page(page),
            "resolution_unit": resolution_unit,
            "icc_profile": icc_profile,
            "filename": os.path.basename(filepath),
            "filepath": filepath,
            "dtype": str(array.dtype),
            "shape": array.shape,
            "page_count": len(tif.pages),
        }

        return array, metadata


def get_image_info(filepath: str) -> dict:
    """Read TIFF metadata without decoding the complete pixel array."""
    if not os.path.exists(filepath):
        raise FileNotFoundError(f"File not found: {filepath}")

    ext = os.path.splitext(filepath)[1].lower()
    if ext not in (".tif", ".tiff"):
        raise ValueError(
            f"Unsupported file format: {ext}. Only .tif/.tiff files are supported."
        )

    with tifffile.TiffFile(filepath) as tif:
        if not tif.pages:
            raise ValueError("TIFF contains no image pages")
        page = tif.pages[0]
        _validate_page(page, len(tif.pages))
        samples = int(_first_value(page.samplesperpixel, 1))
        mode = "RGB" if samples >= 3 else "L"
        compression = getattr(page.compression, "name", str(page.compression))
        resolution_unit = getattr(
            page.resolutionunit, "name", str(page.resolutionunit)
        )
        return {
            "filename": os.path.basename(filepath),
            "filepath": filepath,
            "width": int(page.imagewidth),
            "height": int(page.imagelength),
            "mode": mode,
            "bit_depth": _page_bit_depth(page),
            "compression": compression,
            "dpi": _dpi_from_page(page),
            "resolution_unit": resolution_unit,
            "has_icc_profile": page.tags.get(34675) is not None,
            "file_size": os.path.getsize(filepath),
            "page_count": len(tif.pages),
        }
