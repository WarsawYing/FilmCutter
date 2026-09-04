"""Memory-bounded V2 film-frame detector with no SciPy/Pillow dependency.

The detector first locates continuous film strips from a small TIFF thumbnail,
then applies the selected physical gate geometry along each strip.  An optional
expected count is a soft hint: blank leader/tail cells are never manufactured
to satisfy it.  Experimental refinement may move the four edges a small amount
and is accepted only when its edge score improves while geometry stays valid.
"""

from __future__ import annotations

import base64
import io
from dataclasses import dataclass

import numpy as np
import tifffile

from .thumbnail import DetectionThumbnail, load_detection_thumbnail


# Ratio of image length along the film transport direction to image width
# across the film.  These are physical gates, not localized display labels.
FORMAT_RATIOS = {
    "135": 36.0 / 24.0,
    "135_half": 18.0 / 24.0,
    "65x24": 65.0 / 24.0,
    "645": 41.5 / 56.0,
    "66": 56.0 / 56.0,
    "67": 70.0 / 56.0,
    "68": 76.0 / 56.0,
    "69": 84.0 / 56.0,
    "612": 112.0 / 56.0,
    "617": 168.0 / 56.0,
}
FORMAT_ALIASES = {"135p": "135", "half135": "135_half", "18x24": "135_half"}
SUPPORTED_FORMATS = frozenset({"auto", *FORMAT_RATIOS})
_MAX_FRAMES_PER_SCAN = 72


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

    @property
    def long_size(self) -> int:
        return self.width if self.horizontal else self.height

    @property
    def cross_size(self) -> int:
        return self.height if self.horizontal else self.width


def _grayscale(rgb: np.ndarray) -> np.ndarray:
    values = rgb.astype(np.float32) / 255.0
    return (values[:, :, 0] * 0.2126 + values[:, :, 1] * 0.7152 + values[:, :, 2] * 0.0722)


def _box_filter(values: np.ndarray, radius: int) -> np.ndarray:
    """Fast separable mean filter implemented with NumPy cumulative sums."""
    if radius <= 0:
        return values.astype(np.float32, copy=True)
    width = radius * 2 + 1
    padded = np.pad(values, ((0, 0), (radius, radius)), mode="reflect")
    cumulative = np.cumsum(padded, axis=1, dtype=np.float64)
    cumulative = np.pad(cumulative, ((0, 0), (1, 0)))
    horizontal = (cumulative[:, width:] - cumulative[:, :-width]) / width
    padded = np.pad(horizontal, ((radius, radius), (0, 0)), mode="reflect")
    cumulative = np.cumsum(padded, axis=0, dtype=np.float64)
    cumulative = np.pad(cumulative, ((1, 0), (0, 0)))
    return ((cumulative[width:] - cumulative[:-width]) / width).astype(np.float32)


def _texture_map(gray: np.ndarray) -> np.ndarray:
    local_mean = _box_filter(gray, 3)
    local_square_mean = _box_filter(gray * gray, 3)
    variance = np.maximum(local_square_mean - local_mean * local_mean, 0.0)
    return np.sqrt(variance).astype(np.float32, copy=False)


def _dilate(mask: np.ndarray, iterations: int) -> np.ndarray:
    result = mask.astype(bool, copy=True)
    for _ in range(iterations):
        padded = np.pad(result, 1, mode="constant")
        result = np.logical_or.reduce([
            padded[dy:dy + result.shape[0], dx:dx + result.shape[1]]
            for dy in range(3) for dx in range(3)
        ])
    return result


def _close(mask: np.ndarray, iterations: int) -> np.ndarray:
    grown = _dilate(mask, iterations)
    return ~_dilate(~grown, iterations)


def _runs(active: np.ndarray, min_length: int = 1) -> list[tuple[int, int]]:
    padded = np.pad(active.astype(np.int8), (1, 1))
    changes = np.diff(padded)
    starts = np.flatnonzero(changes == 1)
    stops = np.flatnonzero(changes == -1)
    return [(int(a), int(b)) for a, b in zip(starts, stops) if b - a >= min_length]


def _projection_boxes(mask: np.ndarray) -> list[tuple[int, int, int, int]]:
    """Locate elongated regions using row/column projections.

    Film strips are intentionally constrained geometry, so projection bands
    are both faster and more deterministic than a general component labeller.
    """
    h, w = mask.shape
    boxes: list[tuple[int, int, int, int]] = []
    row_runs = _runs(np.mean(mask, axis=1) > 0.055, max(3, int(h * 0.025)))
    for y0, y1 in row_runs:
        columns = np.mean(mask[y0:y1], axis=0) > 0.12
        for x0, x1 in _runs(columns, max(3, int(w * 0.08))):
            boxes.append((x0, y0, x1 - x0, y1 - y0))
    col_runs = _runs(np.mean(mask, axis=0) > 0.055, max(3, int(w * 0.025)))
    for x0, x1 in col_runs:
        rows = np.mean(mask[:, x0:x1], axis=1) > 0.12
        for y0, y1 in _runs(rows, max(3, int(h * 0.08))):
            boxes.append((x0, y0, x1 - x0, y1 - y0))

    # Texture islands within one physical strip can be separated by a blank
    # frame or tail. Projection bounding boxes join nearby islands when their
    # cross-axis overlap is strong and their long-axis gap is film-sized.
    raw = list(boxes)
    for first in raw:
        for second in raw:
            if first == second:
                continue
            ax, ay, aw, ah = first
            bx, by, bw, bh = second
            cross_overlap_x = max(0, min(ax + aw, bx + bw) - max(ax, bx))
            cross_overlap_y = max(0, min(ay + ah, by + bh) - max(ay, by))
            if cross_overlap_x > min(aw, bw) * 0.70 and max(aw, bw) < max(ah, bh) * 1.3:
                gap = max(0, max(ay, by) - min(ay + ah, by + bh))
                if gap < max(ah, bh) * 1.4:
                    x0, x1 = min(ax, bx), max(ax + aw, bx + bw)
                    y0, y1 = min(ay, by), max(ay + ah, by + bh)
                    boxes.append((x0, y0, x1 - x0, y1 - y0))
            if cross_overlap_y > min(ah, bh) * 0.70 and max(ah, bh) < max(aw, bw) * 1.3:
                gap = max(0, max(ax, bx) - min(ax + aw, bx + bw))
                if gap < max(aw, bw) * 1.4:
                    x0, x1 = min(ax, bx), max(ax + aw, bx + bw)
                    y0, y1 = min(ay, by), max(ay + ah, by + bh)
                    boxes.append((x0, y0, x1 - x0, y1 - y0))

    # Merge near-identical horizontal/vertical projection results.
    kept: list[tuple[int, int, int, int]] = []
    for box in sorted(boxes, key=lambda b: b[2] * b[3], reverse=True):
        x, y, bw, bh = box
        duplicate = False
        for kx, ky, kw, kh in kept:
            ix = max(0, min(x + bw, kx + kw) - max(x, kx))
            iy = max(0, min(y + bh, ky + kh) - max(y, ky))
            union = bw * bh + kw * kh - ix * iy
            if union and (ix * iy) / union > 0.72:
                duplicate = True
                break
        contained = any(
            x >= kx and y >= ky and x + bw <= kx + kw and y + bh <= ky + kh
            for kx, ky, kw, kh in kept
        )
        if not duplicate and not contained:
            kept.append(box)
    return kept


def _strip_candidates(texture: np.ndarray) -> list[StripCandidate]:
    image_h, image_w = texture.shape
    adaptive_floor = float(np.percentile(texture, 40)) * 0.4
    texture_floor = max(0.006, min(adaptive_floor, 0.03))
    grow = max(2, min(5, int(round(min(image_h, image_w) / 250.0))))
    mask = _close(_dilate(texture > texture_floor, grow), grow + 1)
    candidates: list[StripCandidate] = []
    for x, y, width, height in _projection_boxes(mask):
        area_fraction = (width * height) / float(image_w * image_h)
        elongation = max(width, height) / float(max(1, min(width, height)))
        if area_fraction < 0.015 or elongation < 1.7:
            continue
        if min(width, height) < min(image_h, image_w) * 0.12:
            continue
        # Nearly full-canvas landscape/portrait rectangles are valid for
        # short scans, but broad square-ish scanner backgrounds are not.
        if elongation < 2.8 and area_fraction < 0.55:
            continue
        cross_size, long_size = (height, width) if width >= height else (width, height)
        cross_margin = max(2, int(round(cross_size * 0.08)))
        long_margin = max(2, int(round(long_size * 0.02)))
        if width >= height:
            core = texture[y + cross_margin:y + height - cross_margin,
                           x + long_margin:x + width - long_margin]
        else:
            core = texture[y + long_margin:y + height - long_margin,
                           x + cross_margin:x + width - cross_margin]
        if not core.size:
            continue
        texture_mean = float(np.mean(core))
        texture_density = float(np.mean(core > 0.006))
        if texture_mean < 0.0025 or texture_density < 0.08:
            continue
        candidates.append(StripCandidate(x, y, width, height, texture_mean, texture_density))

    horizontal_count = sum(item.horizontal for item in candidates)
    if horizontal_count >= len(candidates) / 2.0:
        return sorted(candidates, key=lambda item: (item.y, item.x))
    return sorted(candidates, key=lambda item: (item.x, item.y))


def _cell_texture_scores(strip: StripCandidate, texture: np.ndarray,
                         cell_count: int) -> list[tuple[float, float]]:
    pitch = strip.long_size / float(cell_count)
    scores = []
    for index in range(cell_count):
        long_start = int(round(index * pitch + pitch * 0.04))
        long_end = int(round((index + 1) * pitch - pitch * 0.04))
        cross_margin = max(1, int(round(strip.cross_size * 0.07)))
        if strip.horizontal:
            region = texture[strip.y + cross_margin:strip.y + strip.height - cross_margin,
                             strip.x + long_start:strip.x + long_end]
        else:
            region = texture[strip.y + long_start:strip.y + long_end,
                             strip.x + cross_margin:strip.x + strip.width - cross_margin]
        scores.append((float(np.mean(region)), float(np.mean(region > 0.006)))
                      if region.size else (0.0, 0.0))
    return scores


def _choose_count(strip: StripCandidate, texture: np.ndarray, ratio: float,
                  expected: int | None) -> tuple[int, list[tuple[float, float]]]:
    nominal = strip.cross_size * ratio * (0.91 / 0.97)
    geometry_count = max(1, int(round(strip.long_size / max(nominal, 1.0))))
    candidates = {geometry_count}
    candidates.update(range(max(1, geometry_count - 2), geometry_count + 3))
    if expected:
        candidates.update(range(max(1, expected - 1), expected + 2))
    best = None
    for count in sorted(candidates):
        if count > _MAX_FRAMES_PER_SCAN:
            continue
        scores = _cell_texture_scores(strip, texture, count)
        means = np.array([s[0] for s in scores])
        densities = np.array([s[1] for s in scores])
        # Prefer geometry first. Raw texture means rise when a wrong count
        # places more separator edges inside cells, so texture is only a weak
        # tie-breaker rather than a dominant reward.
        information = float(np.median(means) * 0.15 + np.median(densities) * 0.003)
        geometry_error = abs(strip.long_size / count - nominal) / max(nominal, 1.0)
        expected_error = abs(count - expected) / max(expected, 1) if expected else 0.0
        objective = information - geometry_error * 0.045 - expected_error * 0.018
        if best is None or objective > best[0]:
            best = (objective, count, scores)
    assert best is not None
    return best[1], best[2]


def _frames_from_strip(strip: StripCandidate, texture: np.ndarray,
                       ratio: float = 1.5, expected: int | None = None) -> list[dict]:
    cell_count, scores = _choose_count(strip, texture, ratio, expected)
    means = np.array([score[0] for score in scores], dtype=np.float32)
    densities = np.array([score[1] for score in scores], dtype=np.float32)
    reference_count = max(1, min(len(scores), int(np.ceil(len(scores) / 2))))
    mean_floor = max(0.0025, float(np.median(np.sort(means)[-reference_count:])) * 0.30)
    density_floor = max(0.10, float(np.median(np.sort(densities)[-reference_count:])) * 0.65)
    confident = [i for i, (mean, density) in enumerate(scores)
                 if mean >= mean_floor and density >= density_floor]
    if not confident:
        return []
    pitch = strip.long_size / float(cell_count)
    frames = []
    for index in range(confident[0], confident[-1] + 1):
        long_start = index * pitch + pitch * 0.015
        long_end = (index + 1) * pitch - pitch * 0.015
        cross_start = strip.cross_size * 0.045
        cross_end = strip.cross_size * 0.955
        if strip.horizontal:
            frame = {"x": strip.x + long_start, "y": strip.y + cross_start,
                     "width": long_end - long_start, "height": cross_end - cross_start}
        else:
            frame = {"x": strip.x + cross_start, "y": strip.y + long_start,
                     "width": cross_end - cross_start, "height": long_end - long_start}
        frames.append(frame)
    return frames


def _edge_score(gray: np.ndarray, frame: dict) -> float:
    h, w = gray.shape
    x0 = max(1, min(w - 2, int(round(frame["x"]))))
    y0 = max(1, min(h - 2, int(round(frame["y"]))))
    x1 = max(x0 + 1, min(w - 2, int(round(frame["x"] + frame["width"]))))
    y1 = max(y0 + 1, min(h - 2, int(round(frame["y"] + frame["height"]))))
    vertical = np.abs(gray[y0:y1, x0 + 1] - gray[y0:y1, x0 - 1]).mean()
    vertical += np.abs(gray[y0:y1, x1 + 1] - gray[y0:y1, x1 - 1]).mean()
    horizontal = np.abs(gray[y0 + 1, x0:x1] - gray[y0 - 1, x0:x1]).mean()
    horizontal += np.abs(gray[y1 + 1, x0:x1] - gray[y1 - 1, x0:x1]).mean()
    return float(vertical + horizontal)


def _refine_frames(frames: list[dict], gray: np.ndarray,
                   ratio: float) -> tuple[list[dict], bool, str | None]:
    if not frames:
        return frames, False, "no_frames"
    refined = []
    baseline_score = sum(_edge_score(gray, f) for f in frames)
    for original in frames:
        current = dict(original)
        max_dx = max(2, int(round(current["width"] * 0.035)))
        max_dy = max(2, int(round(current["height"] * 0.035)))
        for edge, radius in (("left", max_dx), ("right", max_dx),
                             ("top", max_dy), ("bottom", max_dy)):
            best = dict(current)
            best_score = _edge_score(gray, best)
            for delta in range(-radius, radius + 1):
                candidate = dict(current)
                if edge == "left":
                    candidate["x"] += delta; candidate["width"] -= delta
                elif edge == "right":
                    candidate["width"] += delta
                elif edge == "top":
                    candidate["y"] += delta; candidate["height"] -= delta
                else:
                    candidate["height"] += delta
                if candidate["width"] < 8 or candidate["height"] < 8:
                    continue
                score = _edge_score(gray, candidate)
                if score > best_score:
                    best, best_score = candidate, score
            current = best
        actual = (current["width"] / current["height"] if current["width"] >= current["height"]
                  else current["height"] / current["width"])
        target = max(ratio, 1.0 / ratio)
        if abs(actual - target) / target > 0.18:
            return frames, False, "geometry_guard"
        refined.append(current)
    for previous, following in zip(refined, refined[1:]):
        px1, py1 = previous["x"] + previous["width"], previous["y"] + previous["height"]
        fx1, fy1 = following["x"] + following["width"], following["y"] + following["height"]
        overlap = max(0, min(px1, fx1) - max(previous["x"], following["x"])) * max(
            0, min(py1, fy1) - max(previous["y"], following["y"]))
        if overlap > min(previous["width"] * previous["height"],
                         following["width"] * following["height"]) * 0.08:
            return frames, False, "overlap_guard"
    refined_score = sum(_edge_score(gray, f) for f in refined)
    if refined_score <= baseline_score * 1.02:
        return frames, False, "no_score_improvement"
    return refined, True, None


def _map_to_source(frames: list[dict], thumbnail: DetectionThumbnail) -> list[dict]:
    mapped = []
    for index, frame in enumerate(frames):
        x = max(0, int(round(frame["x"] * thumbnail.scale_x)))
        y = max(0, int(round(frame["y"] * thumbnail.scale_y)))
        width = min(max(1, int(round(frame["width"] * thumbnail.scale_x))), thumbnail.source_width - x)
        height = min(max(1, int(round(frame["height"] * thumbnail.scale_y))), thumbnail.source_height - y)
        mapped.append({"index": index, "x": x, "y": y, "width": width, "height": height})
    return mapped


def _preview_base64(rgb: np.ndarray, max_width: int = 500) -> str:
    if rgb.shape[1] > max_width:
        step = max(1, int(np.ceil(rgb.shape[1] / max_width)))
        rgb = rgb[::step, ::step]
    buffer = io.BytesIO()
    tifffile.imwrite(buffer, rgb, photometric="rgb", compression=None)
    return base64.b64encode(buffer.getvalue()).decode("ascii")


def _auto_ratio(strips: list[StripCandidate], texture: np.ndarray,
                expected_count: int | None) -> float:
    # Select geometry with the smallest aggregate pitch residual.  A tiny
    # prior for 135 resolves physically indistinguishable 135/6×9 scans while
    # the response still honestly reports format "auto".
    best = None
    total_long = sum(strip.long_size for strip in strips) or 1
    for format_id, ratio in FORMAT_RATIOS.items():
        counts = 0
        residual = 0.0
        for strip in strips:
            expected = (max(1, round(expected_count * strip.long_size / total_long))
                        if expected_count else None)
            count, _ = _choose_count(strip, texture, ratio, expected)
            pitch = strip.long_size / count
            nominal = strip.cross_size * ratio * (0.91 / 0.97)
            residual += abs(pitch - nominal) / max(nominal, 1.0)
            counts += count
        if expected_count:
            residual += abs(counts - expected_count) / max(expected_count, 1) * 0.35
        if format_id == "135":
            residual -= 0.01
        if best is None or residual < best[0]:
            best = (residual, ratio)
    return best[1] if best else FORMAT_RATIOS["135"]


def detect_file_v2(filepath: str, format_id: str = "auto",
                   expected_count: int | None = None,
                   refine_contour: bool = False) -> dict:
    format_id = FORMAT_ALIASES.get(format_id, format_id)
    if format_id not in SUPPORTED_FORMATS:
        raise ValueError(f"Unsupported film format: {format_id}")
    if expected_count is not None:
        expected_count = int(expected_count)
        if expected_count < 1 or expected_count > _MAX_FRAMES_PER_SCAN:
            raise ValueError("Expected frame count must be between 1 and 72")

    thumbnail = load_detection_thumbnail(filepath)
    gray = _grayscale(thumbnail.rgb)
    texture = _texture_map(gray)
    strips = _strip_candidates(texture)
    ratio = (_auto_ratio(strips, texture, expected_count) if format_id == "auto"
             else FORMAT_RATIOS[format_id])
    total_long = sum(strip.long_size for strip in strips) or 1
    thumbnail_frames = []
    for strip in strips:
        expected = (max(1, round(expected_count * strip.long_size / total_long))
                    if expected_count else None)
        thumbnail_frames.extend(_frames_from_strip(strip, texture, ratio, expected))

    refinement_applied = False
    fallback_reason = None
    if refine_contour:
        thumbnail_frames, refinement_applied, fallback_reason = _refine_frames(
            thumbnail_frames, gray, ratio)
    frames = _map_to_source(thumbnail_frames, thumbnail)
    return {
        "frames": frames,
        "frame_count": len(frames),
        "found_count": len(frames),
        "expected_count": expected_count,
        "width": thumbnail.source_width,
        "height": thumbnail.source_height,
        "bit_depth": thumbnail.bit_depth,
        "file_name": thumbnail.filename,
        "preview_b64": _preview_base64(thumbnail.rgb),
        "detector": "v2",
        "strip_count": len(strips),
        "selected_format": format_id,
        "estimated_format": format_id if format_id != "auto" else "auto",
        "refinement_applied": refinement_applied,
        "refinement_fallback_reason": fallback_reason,
    }
