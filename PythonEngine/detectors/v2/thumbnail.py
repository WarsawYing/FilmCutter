"""Memory-bounded TIFF thumbnail loading for Detector V2.

Detection never needs all 16-bit source pixels resident in RAM.  This module
opens directly memory-mappable TIFFs in place and falls back to a temporary
memory map for compressed or non-contiguous pages.  A small area-sampled RGB
image is then produced for detection and preview generation.
"""

from dataclasses import dataclass
import math
import os

import numpy as np
import tifffile


@dataclass(frozen=True)
class DetectionThumbnail:
    """A normalized thumbnail and its mapping back to source coordinates."""

    rgb: np.ndarray
    source_width: int
    source_height: int
    scale_x: float
    scale_y: float
    bit_depth: int
    filename: str


def _normalize_sample_layout(array: np.ndarray, samples: int) -> np.ndarray:
    """Return a grayscale or H×W×C view without copying the source image."""
    if (
        array.ndim == 3
        and samples in (3, 4)
        and array.shape[0] == samples
        and array.shape[-1] != samples
    ):
        array = np.moveaxis(array, 0, -1)
    if array.ndim == 3 and array.shape[-1] > 3:
        array = array[:, :, :3]
    return array


def _open_page_as_memmap(filepath: str):
    """Open page zero as a memory map and return it with basic TIFF metadata."""
    with tifffile.TiffFile(filepath) as tif:
        if not tif.pages:
            raise ValueError("TIFF contains no image pages")
        if len(tif.pages) != 1:
            raise ValueError(
                f"Multi-page TIFF is not supported yet ({len(tif.pages)} pages)"
            )
        page = tif.pages[0]
        compression = getattr(page.compression, "name", str(page.compression))
        if compression not in {"NONE", "1"}:
            raise ValueError(
                f"Compressed TIFF is not supported in FilmCutter 1.1 ({compression}). "
                "Export an uncompressed TIFF."
            )
        samples = int(page.samplesperpixel or 1)
        bit_depth_value = page.bitspersample or 8
        if isinstance(bit_depth_value, (tuple, list)):
            bit_depth_value = bit_depth_value[0]
        bit_depth = int(bit_depth_value)

        try:
            # This is zero-copy for the uncompressed contiguous Flextight TIFFs
            # used by the sample set.
            array = tifffile.memmap(filepath, page=0, mode="r")
        except (ValueError, TypeError):
            # tifffile decodes to a temporary disk-backed map.  Peak RAM stays
            # bounded even though compressed source pixels must be decoded.
            array = page.asarray(out="memmap")

    return _normalize_sample_layout(array, samples), bit_depth


def _sample_rgb(array: np.ndarray, step: int) -> np.ndarray:
    """Approximate area sampling using four points from every source block."""
    height, width = array.shape[:2]
    out_h = max(1, height // step)
    out_w = max(1, width // step)

    if step == 1:
        offsets = [(0, 0)]
    else:
        low = min(step - 1, max(0, step // 3))
        high = min(step - 1, max(0, (2 * step) // 3))
        offsets = list(dict.fromkeys([
            (low, low),
            (low, high),
            (high, low),
            (high, high),
        ]))

    accumulator = np.zeros((out_h, out_w, 3), dtype=np.float32)
    for offset_y, offset_x in offsets:
        sampled = array[
            offset_y:offset_y + out_h * step:step,
            offset_x:offset_x + out_w * step:step,
        ]
        if sampled.ndim == 2:
            values = sampled.astype(np.float32, copy=False)
            accumulator += values[:, :, None]
        else:
            values = sampled[:, :, :3].astype(np.float32, copy=False)
            accumulator += values

    accumulator /= float(len(offsets))
    if array.ndim == 2:
        accumulator[:, :, 1] = accumulator[:, :, 0]
        accumulator[:, :, 2] = accumulator[:, :, 0]
    return accumulator


def load_detection_thumbnail(
    filepath: str,
    max_side: int = 2400,
) -> DetectionThumbnail:
    """Load a normalized, memory-bounded detection image from a TIFF file."""
    if not os.path.exists(filepath):
        raise FileNotFoundError(f"File not found: {filepath}")

    array, bit_depth = _open_page_as_memmap(filepath)
    source_h, source_w = array.shape[:2]
    step = max(1, int(math.ceil(max(source_h, source_w) / max_side)))
    sampled = _sample_rgb(array, step)

    # One common luminance-derived stretch keeps RGB relationships intact and
    # makes the texture thresholds stable across positive and negative scans.
    luminance = (
        sampled[:, :, 0] * 0.2126
        + sampled[:, :, 1] * 0.7152
        + sampled[:, :, 2] * 0.0722
    )
    low, high = np.percentile(luminance, (0.5, 99.5))
    spread = max(float(high - low), 1.0)
    rgb = np.clip((sampled - low) * (255.0 / spread), 0, 255).astype(np.uint8)

    thumb_h, thumb_w = rgb.shape[:2]
    return DetectionThumbnail(
        rgb=rgb,
        source_width=source_w,
        source_height=source_h,
        scale_x=source_w / float(thumb_w),
        scale_y=source_h / float(thumb_h),
        bit_depth=bit_depth,
        filename=os.path.basename(filepath),
    )
