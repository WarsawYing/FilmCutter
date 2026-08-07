"""
Image processor module for FilmCutter.
Handles frame cutting, color conversion, and metadata-embedded TIFF output.
"""

import os
import numpy as np

from debug_log import debug_log


def cut_frames(image_array: np.ndarray, frames: list, metadata: dict,
               convert: bool = False, border_px: int = 4) -> list:
    """Cut individual frames from the full scan image."""
    result = []

    for i, frame in enumerate(frames):
        x, y, w, h = frame['x'], frame['y'], frame['width'], frame['height']
        border = max(0, int(border_px))

        # Detection and manual editing describe the content rectangle.
        # Padding belongs here so the UI border setting affects final output
        # without being applied twice by the detector and processor.
        x = max(0, int(x) - border)
        y = max(0, int(y) - border)
        x2 = min(image_array.shape[1], int(frame['x']) + int(w) + border)
        y2 = min(image_array.shape[0], int(frame['y']) + int(h) + border)
        w = max(0, x2 - x)
        h = max(0, y2 - y)

        if w == 0 or h == 0:
            raise ValueError(f"Frame {i} is outside the image bounds")

        if len(image_array.shape) == 3:
            frame_data = image_array[y:y+h, x:x+w, :].copy()
        else:
            frame_data = image_array[y:y+h, x:x+w].copy()

        if convert:
            frame_data = invert_image(frame_data, metadata)

        debug_log(
            f"[CUT] frame {i}: x={x} y={y} w={w} h={h} "
            f"data_shape={frame_data.shape} dtype={frame_data.dtype}"
        )
        result.append({
            'data': frame_data,
            # Source color and resolution metadata travel with every crop so
            # the writer does not have to reopen the very large input TIFF.
            'source_metadata': metadata,
            'index': i,
            'width': w,
            'height': h,
            'x': x,
            'y': y,
        })

    return result


def invert_image(image_array: np.ndarray, metadata: dict) -> np.ndarray:
    """Perform inversion of the image (negative -> positive)."""
    if np.issubdtype(image_array.dtype, np.unsignedinteger):
        max_value = np.iinfo(image_array.dtype).max
        return (max_value - image_array).astype(image_array.dtype, copy=False)

    if np.issubdtype(image_array.dtype, np.floating):
        return (1.0 - image_array).astype(image_array.dtype, copy=False)

    raise TypeError(f"Unsupported image dtype for inversion: {image_array.dtype}")


# ---- Metadata / EXIF writing ----

def _build_xmp_packet(meta: dict) -> bytes:
    """Build a minimal XMP packet with custom film metadata.
    Notes are included here because tifffile reserves TIFF tag 270 (ImageDescription)."""
    parts = ['<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>',
             '<x:xmpmeta xmlns:x="adobe:ns:meta/">',
             '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">',
             '<rdf:Description>']
    if meta.get('film_stock'):
        parts.append(f'<FilmStock>{_xml_escape(meta["film_stock"])}</FilmStock>')
    if meta.get('push_pull') and meta['push_pull'] != 'None':
        parts.append(f'<PushPull>{_xml_escape(meta["push_pull"])}</PushPull>')
    if meta.get('scanner'):
        parts.append(f'<Scanner>{_xml_escape(meta["scanner"])}</Scanner>')
    if meta.get('notes'):
        parts.append(f'<Notes>{_xml_escape(meta["notes"])}</Notes>')
    parts.append('</rdf:Description></rdf:RDF></x:xmpmeta>')
    parts.append('<?xpacket end="w"?>')
    return '\n'.join(parts).encode('utf-8')


def _xml_escape(s: str) -> str:
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')


def _parse_aperture(ap_str: str):
    """Parse 'f/5.6' → (56, 10) as rational numerator/denominator."""
    if not ap_str or ap_str == 'Not Available':
        return None
    s = ap_str.lower().replace('f/', '').strip()
    try:
        val = float(s)
        num = int(round(val * 10))
        return (num, 10)
    except ValueError:
        return None


def _format_exif_date(date_str: str) -> str:
    """Convert '2026-05-01' → '2026:05:01 00:00:00'."""
    if not date_str:
        return ''
    s = date_str.replace('-', ':').strip()
    if len(s) == 10:
        s += ' 00:00:00'
    return s


def _build_extratags(meta: dict) -> list:
    """Build tifffile extratags list from roll metadata dict."""
    tags = []

    camera = meta.get('camera', '')
    lens = meta.get('lens', '')
    aperture = meta.get('aperture', '')
    date_str = meta.get('date', '')

    if camera:
        tags.append((271, 2, 0, camera, True))      # Make
        tags.append((272, 2, 0, camera, True))      # Model (same, since camera includes both)

    if lens:
        tags.append((42036, 2, 0, lens, True))      # LensModel

    ap = _parse_aperture(aperture)
    if ap:
        tags.append((33437, 5, 1, ap, True))        # FNumber

    if date_str:
        exif_date = _format_exif_date(date_str)
        tags.append((306, 2, 0, exif_date, True))    # DateTime

    # Notes go in XMP because tifffile reserves tag 270 (ImageDescription)

    # XMP packet for non-EXIF fields
    xmp = _build_xmp_packet(meta)
    if xmp:
        tags.append((700, 7, len(xmp), xmp, True))   # XMP

    return tags


# ---- TIFF saving ----

def save_frame_as_tiff(frame_data: np.ndarray, output_path: str,
                       roll_metadata: dict = None,
                       source_metadata: dict = None) -> str:
    """
    Save a single frame as an uncompressed 16-bit TIFF file with EXIF/XMP metadata.

    Args:
        frame_data: numpy array of the frame
        output_path: Full output file path (should end in .tif)
        roll_metadata: Optional dict with camera, lens, film_stock, etc.
        source_metadata: ICC and resolution metadata from the source TIFF.

    Returns:
        The output path string
    """
    import tifffile

    output_dir = os.path.dirname(output_path)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir, exist_ok=True)

    debug_log(f"[SAVE] shape={frame_data.shape} dtype={frame_data.dtype}")

    # Always produce 16-bit output
    if frame_data.dtype == np.uint8:
        frame_data = (frame_data.astype(np.uint32) * 257).clip(0, 65535).astype(np.uint16)
    elif frame_data.dtype != np.uint16:
        frame_data = np.clip(frame_data, 0, 65535).astype(np.uint16)

    if frame_data.ndim == 3 and frame_data.shape[2] >= 3:
        frame_data = frame_data[:, :, :3]

    # Preserve color interpretation. Pixel values alone are insufficient for
    # color-managed film scans; losing the ICC tag can visibly change output.
    source_metadata = source_metadata or {}
    extratags = _build_extratags(roll_metadata or {})
    icc_profile = source_metadata.get("icc_profile")
    if icc_profile:
        extratags.append(
            (34675, 7, len(icc_profile), icc_profile, False)
        )

    resolution = source_metadata.get("dpi", (0, 0))
    resolution_unit = source_metadata.get("resolution_unit", "NONE")
    write_options = {}
    if (
        len(resolution) == 2
        and resolution[0] > 0
        and resolution[1] > 0
        and resolution_unit in {"INCH", "CENTIMETER"}
    ):
        write_options["resolution"] = resolution
        write_options["resolutionunit"] = resolution_unit

    # "xb" is deliberate: it atomically reserves a new path and refuses to
    # overwrite a file created after the engine's earlier collision check.
    created = False
    try:
        with open(output_path, "xb") as output_file:
            created = True
            tifffile.imwrite(
                output_file,
                frame_data,
                compression=None,
                extratags=extratags if extratags else None,
                **write_options,
            )
    except Exception:
        # A failed encoder must not leave a corrupt half-written TIFF behind.
        if created:
            try:
                os.unlink(output_path)
            except FileNotFoundError:
                pass
        raise

    debug_log(
        f"[META] wrote {len(extratags)} tags to "
        f"{os.path.basename(output_path)}"
    )

    return output_path


def get_output_filename(batch_name: str, frame_number: int) -> str:
    """
    Generate the output filename for a frame.
    Format: {xxx}{yyy} where xxx is batch name, yyy is sequential number (1-based, zero-padded).
    """
    safe_name = batch_name.translate(
        str.maketrans('/\\:*?"<>|', '---------')
    ).strip().rstrip("_-")
    if not safe_name:
        safe_name = "Film"
    return f"{safe_name}_{frame_number:03d}.tif"
