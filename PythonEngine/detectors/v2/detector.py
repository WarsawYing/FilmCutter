"""Constraint-driven, coarse-to-fine frame detector.

V2 deliberately keeps the original detector untouched.  It currently focuses
on 135 scans and handles both layouts observed in real Flextight output:

* horizontal strips containing landscape frames;
* vertical strips containing portrait-oriented frame rectangles.

The algorithm uses texture to locate complete film strips, then divides each
strip along its long axis using the repeated 135 frame geometry.  Frame count
is an upper bound, never a target: low-information tail cells are rejected.
"""

import base64
import io
from dataclasses import dataclass

import numpy as np
from PIL import Image
from scipy.ndimage import (
    binary_closing,
    binary_dilation,
    find_objects,
    gaussian_filter,
    label,
)

from .thumbnail import DetectionThumbnail, load_detection_thumbnail


_MAX_135_FRAMES_PER_SCAN = 12


@dataclass(frozen=True)
class StripCandidate:
    x: int
    y: int
    width: int
    height: int
    texture_mean: float
    texture_density: float

    @property
    def horizontal(self) -> bool:
        return self.width >= self.height


def _grayscale(rgb: np.ndarray) -> np.ndarray:
    values = rgb.astype(np.float32) / 255.0
    return (
        values[:, :, 0] * 0.2126
        + values[:, :, 1] * 0.7152
        + values[:, :, 2] * 0.0722
    )


def _texture_map(gray: np.ndarray) -> np.ndarray:
    """Return local standard deviation without creating a full-size window."""
    local_mean = gaussian_filter(gray, sigma=2.0, mode="reflect")
    local_square_mean = gaussian_filter(gray * gray, sigma=2.0, mode="reflect")
    variance = np.maximum(local_square_mean - local_mean * local_mean, 0.0)
    return np.sqrt(variance).astype(np.float32, copy=False)


def _strip_candidates(texture: np.ndarray) -> list:
    """Find elongated textured components that can contain repeated frames."""
    image_h, image_w = texture.shape
    adaptive_floor = float(np.percentile(texture, 40)) * 0.4
    texture_floor = max(0.006, min(adaptive_floor, 0.03))
    mask = texture > texture_floor

    # A few pixels join texture islands inside the same film strip while the
    # much wider scanner background gaps remain separate.
    grow = max(2, min(5, int(round(min(image_h, image_w) / 250.0))))
    mask = binary_dilation(mask, iterations=grow)
    mask = binary_closing(mask, iterations=grow + 1)

    components, count = label(mask)
    candidates = []
    for slices in find_objects(components, max_label=count):
        if slices is None:
            continue
        y_slice, x_slice = slices
        x, y = x_slice.start, y_slice.start
        width = x_slice.stop - x
        height = y_slice.stop - y
        area_fraction = (width * height) / float(image_w * image_h)
        elongation = max(width, height) / float(max(1, min(width, height)))

        if area_fraction < 0.015 or elongation < 2.8:
            continue
        if width < image_w * 0.08 or height < image_h * 0.08:
            continue

        cross_size = height if width >= height else width
        long_size = width if width >= height else height
        cross_margin = max(2, int(round(cross_size * 0.08)))
        long_margin = max(2, int(round(long_size * 0.02)))
        if width >= height:
            core = texture[
                y + cross_margin:y + height - cross_margin,
                x + long_margin:x + width - long_margin,
            ]
        else:
            core = texture[
                y + long_margin:y + height - long_margin,
                x + cross_margin:x + width - cross_margin,
            ]
        if core.size == 0:
            continue

        texture_mean = float(np.mean(core))
        texture_density = float(np.mean(core > 0.006))

        # Reject scanner masks and clear tail regions that only have a strong
        # outline.  Their large bounding box previously looked like a frame.
        if texture_mean < 0.0025 or texture_density < 0.08:
            continue

        candidates.append(StripCandidate(
            x=x,
            y=y,
            width=width,
            height=height,
            texture_mean=texture_mean,
            texture_density=texture_density,
        ))

    # Reading order follows physical strips: top-to-bottom rows for horizontal
    # layouts, left-to-right columns for vertical layouts.
    horizontal_count = sum(candidate.horizontal for candidate in candidates)
    if horizontal_count >= len(candidates) / 2.0:
        return sorted(candidates, key=lambda item: (item.y, item.x))
    return sorted(candidates, key=lambda item: (item.x, item.y))


def _cell_texture_scores(
    strip: StripCandidate,
    texture: np.ndarray,
    cell_count: int,
) -> list:
    """Measure information inside each repeated geometry cell."""
    long_size = strip.width if strip.horizontal else strip.height
    cross_size = strip.height if strip.horizontal else strip.width
    pitch = long_size / float(cell_count)
    scores = []

    for cell_index in range(cell_count):
        long_start = int(round(cell_index * pitch + pitch * 0.04))
        long_end = int(round((cell_index + 1) * pitch - pitch * 0.04))
        cross_margin = max(1, int(round(cross_size * 0.07)))
        if strip.horizontal:
            region = texture[
                strip.y + cross_margin:strip.y + strip.height - cross_margin,
                strip.x + long_start:strip.x + long_end,
            ]
        else:
            region = texture[
                strip.y + long_start:strip.y + long_end,
                strip.x + cross_margin:strip.x + strip.width - cross_margin,
            ]
        if region.size == 0:
            scores.append((0.0, 0.0))
        else:
            scores.append((
                float(np.mean(region)),
                float(np.mean(region > 0.006)),
            ))
    return scores


def _frames_from_strip(
    strip: StripCandidate,
    texture: np.ndarray,
) -> list:
    """Apply repeated 135 geometry and reject only terminal blank cells.

    A legitimate photograph can be almost textureless (sky, fog, a studio
    backdrop, or a heavily exposed negative).  Texture is therefore used to
    locate the occupied *span* of a strip, not to delete arbitrary cells from
    the middle.  Once two confident cells bracket a weak cell, 135's repeated
    physical geometry is stronger evidence than the weak texture score.
    """
    long_size = strip.width if strip.horizontal else strip.height
    cross_size = strip.height if strip.horizontal else strip.width

    # Film borders and perforations make the detected strip about 7–10% wider
    # than the image area.  Consequently one cell is about 1.4 strip widths,
    # while its final content rectangle remains close to the 3:2 gate ratio.
    nominal_pitch = cross_size * 1.40
    cell_count = int(round(long_size / max(nominal_pitch, 1.0)))
    cell_count = max(1, min(cell_count, _MAX_135_FRAMES_PER_SCAN))
    pitch = long_size / float(cell_count)

    scores = _cell_texture_scores(strip, texture, cell_count)
    means = np.array([score[0] for score in scores], dtype=np.float32)
    densities = np.array([score[1] for score in scores], dtype=np.float32)

    reference_count = max(1, min(len(scores), int(np.ceil(len(scores) / 2))))
    strongest_means = np.sort(means)[-reference_count:]
    strongest_densities = np.sort(densities)[-reference_count:]
    # A dark night frame may legitimately contain much less texture than a
    # daylight frame beside it.  Keep the mean threshold deliberately loose;
    # the density threshold below is what rejects a uniformly blank tail.
    mean_floor = max(0.0025, float(np.median(strongest_means)) * 0.30)
    density_floor = max(0.10, float(np.median(strongest_densities)) * 0.65)

    confident_cells = [
        cell_index
        for cell_index, (mean_score, density_score) in enumerate(scores)
        if mean_score >= mean_floor and density_score >= density_floor
    ]
    if not confident_cells:
        return []

    # Film advances continuously through a scanner.  Empty leader/tail can
    # only be trimmed outside the first/last confident frame; a weak cell
    # between them is a low-detail photograph, not a hole in the roll.
    first_occupied = confident_cells[0]
    last_occupied = confident_cells[-1]

    frames = []
    for cell_index in range(first_occupied, last_occupied + 1):
        long_start = cell_index * pitch + pitch * 0.015
        long_end = (cell_index + 1) * pitch - pitch * 0.015
        cross_start = cross_size * 0.045
        cross_end = cross_size * 0.955

        if strip.horizontal:
            frames.append({
                "x": strip.x + long_start,
                "y": strip.y + cross_start,
                "width": long_end - long_start,
                "height": cross_end - cross_start,
                "orientation": "horizontal",
            })
        else:
            frames.append({
                "x": strip.x + cross_start,
                "y": strip.y + long_start,
                "width": cross_end - cross_start,
                "height": long_end - long_start,
                "orientation": "vertical",
            })
    return frames


def _map_to_source(frames: list, thumbnail: DetectionThumbnail) -> list:
    """Map rectangles back with independent X/Y scale factors."""
    mapped = []
    for frame in frames:
        x = max(0, int(round(frame["x"] * thumbnail.scale_x)))
        y = max(0, int(round(frame["y"] * thumbnail.scale_y)))
        width = max(1, int(round(frame["width"] * thumbnail.scale_x)))
        height = max(1, int(round(frame["height"] * thumbnail.scale_y)))
        width = min(width, thumbnail.source_width - x)
        height = min(height, thumbnail.source_height - y)
        mapped.append({
            "index": 0,
            "x": x,
            "y": y,
            "width": width,
            "height": height,
        })

    for index, frame in enumerate(mapped):
        frame["index"] = index
    return mapped


def _preview_base64(rgb: np.ndarray, max_width: int = 500) -> str:
    image = Image.fromarray(rgb)
    if image.width > max_width:
        target_height = max(1, int(round(image.height * max_width / image.width)))
        image = image.resize((max_width, target_height), Image.Resampling.LANCZOS)
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=78)
    return base64.b64encode(buffer.getvalue()).decode("ascii")


def detect_file_v2(filepath: str, format_id: str = "auto") -> dict:
    """Detect 135 frames directly from a TIFF without a full in-RAM decode."""
    if format_id not in ("auto", "135", "135p"):
        raise ValueError(
            f"Detector V2 currently supports auto/135/135p, got {format_id!r}"
        )

    thumbnail = load_detection_thumbnail(filepath)
    gray = _grayscale(thumbnail.rgb)
    texture = _texture_map(gray)
    strips = _strip_candidates(texture)

    thumbnail_frames = []
    for strip in strips:
        thumbnail_frames.extend(_frames_from_strip(strip, texture))

    frames = _map_to_source(thumbnail_frames, thumbnail)
    return {
        "frames": frames,
        "frame_count": len(frames),
        "width": thumbnail.source_width,
        "height": thumbnail.source_height,
        "bit_depth": thumbnail.bit_depth,
        "file_name": thumbnail.filename,
        "preview_b64": _preview_base64(thumbnail.rgb),
        "detector": "v2",
        "strip_count": len(strips),
        "estimated_format": "135",
    }
