"""
Frame detection module for FilmCutter.
Detects individual film frames from scanned film strips (Hasselblad X5).

Two-pass algorithm:
  Pass 1 - Global IQR percentile → find ALL gap regions
            Classify gaps by size: "strip gaps" (wide, between strips) vs "frame gaps" (narrow, between frames)
  Pass 2 - Ratio to local-maximum → precise frame boundaries within each film region

IQR (P90-P10 per row): frames have HIGH variance (image content), gaps have LOW variance (uniform film base).

Supports format-based detection where an expected aspect ratio is provided as a prior.
"""

import numpy as np
from scipy.ndimage import gaussian_filter1d, maximum_filter1d
from scipy.signal import find_peaks

from debug_log import debug_log


# ---- Format presets ----

FORMAT_PRESETS = {
    '135':   {'ratio': 3/2,   'name': '135 / 35mm Landscape (3:2)'},
    '135p':  {'ratio': 2/3,   'name': '135 / 35mm Portrait (2:3)'},
    '65x24': {'ratio': 65/24, 'name': '65×24mm (2.71:1)'},
    '645':   {'ratio': 4/3,   'name': '645 / 6×4.5 (4:3)'},
    '66':    {'ratio': 1.0,   'name': '6×6 (1:1)'},
    '67':    {'ratio': 7/6,   'name': '6×7 (~5:4)'},
    '68':    {'ratio': 8/6,   'name': '6×8 (4:3)'},
    '69':    {'ratio': 9/6,   'name': '6×9 (3:2)'},
    '612':   {'ratio': 12/6,  'name': '6×12 (2:1)'},
    '617':   {'ratio': 17/6,  'name': '6×17 (2.83:1)'},
}


def _compute_row_iqr(gray: np.ndarray, sigma: float = 3) -> np.ndarray:
    """Compute IQR (P90-P10) per row with light smoothing."""
    h, w = gray.shape
    row_iqr = np.zeros(h, dtype=np.float32)
    p10_idx = int(w * 0.10)
    p90_idx = int(w * 0.90)
    for y in range(h):
        s = np.sort(gray[y, :])
        row_iqr[y] = s[p90_idx] - s[p10_idx]
    return gaussian_filter1d(row_iqr, sigma=sigma)


def _find_strips_via_columns(gray: np.ndarray) -> list:
    """Find vertical film strips by analyzing column brightness."""
    h, w = gray.shape
    col_mean = np.mean(gray, axis=0)
    col_smooth = gaussian_filter1d(col_mean, sigma=10)
    threshold = col_smooth.mean() * 0.9
    is_film = col_smooth > threshold
    strips = []
    in_strip = False
    start = 0
    for x in range(w):
        if is_film[x] and not in_strip:
            start = x
            in_strip = True
        elif not is_film[x] and in_strip:
            if x - start > 200:
                strips.append((start, x))
            in_strip = False
    if in_strip and w - start > 200:
        strips.append((start, w))
    return strips


def _find_gaps_global(iqr_signal: np.ndarray) -> list:
    """Find ALL gap regions using global percentile threshold."""
    valid = iqr_signal[iqr_signal > np.percentile(iqr_signal, 3)]
    th = np.percentile(valid, 16) if len(valid) > 10 else np.percentile(iqr_signal, 16)
    
    is_gap = iqr_signal < th
    gaps = []
    in_gap = False
    gs = 0
    for y in range(len(iqr_signal)):
        if is_gap[y] and not in_gap:
            gs = y
            in_gap = True
        elif not is_gap[y] and in_gap:
            if y - gs >= 12:
                gaps.append((gs, y))
            in_gap = False
    if in_gap and len(iqr_signal) - gs >= 12:
        gaps.append((gs, len(iqr_signal)))
    return gaps


def _find_gaps_ratio(iqr_signal: np.ndarray) -> list:
    """Find gaps by ratio to local-maximum IQR."""
    max_window = max(len(iqr_signal) // 30, 151)
    if max_window % 2 == 0:
        max_window += 1
    local_max = maximum_filter1d(iqr_signal, size=min(max_window, len(iqr_signal)), mode='reflect')
    
    global_ref = np.percentile(iqr_signal, 85)
    reference = np.maximum(local_max, global_ref * 0.1)
    reference = np.maximum(reference, 0.001)
    
    ratio = iqr_signal / reference
    
    is_gap = ratio < 0.20
    gaps = []
    in_gap = False
    gs = 0
    for y in range(len(iqr_signal)):
        if is_gap[y] and not in_gap:
            gs = y
            in_gap = True
        elif not is_gap[y] and in_gap:
            if y - gs >= 12:
                gaps.append((gs, y))
            in_gap = False
    if in_gap and len(iqr_signal) - gs >= 12:
        gaps.append((gs, len(iqr_signal)))
    return gaps


def _merge_gaps(gaps: list, merge_dist: int = 50) -> list:
    """Merge gaps closer than merge_dist."""
    if not gaps:
        return []
    merged = [gaps[0]]
    for gs, ge in gaps[1:]:
        if gs - merged[-1][1] < merge_dist:
            merged[-1] = (merged[-1][0], ge)
        else:
            merged.append((gs, ge))
    return merged


def _classify_gaps(gaps: list, iqr_signal: np.ndarray):
    """Classify gaps into 'strip' (between different films) vs 'frame' (between frames in same film)."""
    if not gaps:
        return {'strip': [], 'frame': []}

    sizes = np.array([ge - gs for gs, ge in gaps])
    median_sz = np.median(sizes)
    global_iqr_p50 = np.percentile(iqr_signal, 50)
    
    strip_gaps = []
    frame_gaps = []
    
    for gs, ge in gaps:
        sz = ge - gs
        region_iqr = iqr_signal[gs:ge]
        region_iqr_mean = np.mean(region_iqr) if len(region_iqr) > 0 else 0
        
        is_strip_by_size = sz > max(median_sz * 3, 200)
        is_strip_by_iqr = region_iqr_mean < global_iqr_p50 * 0.2
        
        if is_strip_by_size or is_strip_by_iqr:
            strip_gaps.append((gs, ge))
        else:
            frame_gaps.append((gs, ge))
    
    return {'strip': strip_gaps, 'frame': frame_gaps}


def _filter_frames(frames: list, strip_width: int, expected_ratio: float = None) -> list:
    """Filter frames by size clustering — real frames are similar in size, noise is random."""
    if not frames:
        return []

    # Step 1: Drop impossibly small and extreme-aspect junk
    frames = [f for f in frames if f['width'] >= 80 and f['height'] >= 80]
    frames = [f for f in frames if 0.12 < f['width'] / max(f['height'], 1) < 8.0]
    if not frames:
        return frames

    if len(frames) <= 3:
        frames.sort(key=lambda r: (r['y'], r['x']))
        return frames

    # Step 2: Size clustering — real frames cluster around a common area
    areas = np.array([f['width'] * f['height'] for f in frames])
    median_area = np.median(areas)

    # Use MAD (median absolute deviation) for robust outlier detection
    mad = np.median(np.abs(areas - median_area))
    if mad == 0:
        mad = median_area * 0.15
    z_scores = np.abs(areas - median_area) / (mad * 1.4826 + 0.001)

    # Keep frames within 2.5 MAD of median area (generous but excludes far outliers)
    clustered = [f for i, f in enumerate(frames) if z_scores[i] < 2.5]

    if len(clustered) >= 2:
        frames = clustered
    # If clustering removed everything, keep original

    # Step 3: If we know the expected ratio, prefer frames that match it
    if expected_ratio and len(frames) > 4:
        scored = []
        for f in frames:
            ar = f['width'] / max(f['height'], 1)
            err = abs(ar - expected_ratio) / expected_ratio
            scored.append((err, f))
        scored.sort(key=lambda x: x[0])
        # Take frames within 40% ratio error of expected
        frames = [f for err, f in scored if err < 0.40]

    frames.sort(key=lambda r: (r['y'], r['x']))
    return frames


def _remove_lone_narrow_gaps(gaps: list, min_gap_width: int = 8) -> list:
    """Remove gaps narrower than min_gap_width (false positives inside uniform regions)."""
    return [(gs, ge) for gs, ge in gaps if (ge - gs) >= min_gap_width]


def detect_frames(image_array: np.ndarray, border_px: int = 4) -> list:
    """
    Detect individual film frames in a scanned image (auto mode).

    Args:
        image_array: numpy array (H, W) grayscale or (H, W, C) RGB.
        border_px: pixels of border to leave around each frame (3-5).

    Returns:
        list of dicts: [{'x', 'y', 'width', 'height', 'index'}, ...]
    """
    if image_array is None or image_array.size == 0:
        return []

    if len(image_array.shape) == 3:
        grayscale = np.mean(image_array.astype(np.float32), axis=2)
    else:
        grayscale = image_array.astype(np.float32)

    height, width = grayscale.shape
    strips = _find_strips_via_columns(grayscale)
    if not strips:
        strips = [(0, width)]

    all_frames = []

    for sx, ex in strips:
        strip = grayscale[:, sx:ex]
        sw = ex - sx

        iqr_signal = _compute_row_iqr(strip, sigma=3)

        # --- Pass 1: Find ALL gaps via global percentile ---
        all_gaps = _find_gaps_global(iqr_signal)
        all_gaps = _merge_gaps(all_gaps)

        # --- Classify: strip gaps vs frame gaps ---
        classification = _classify_gaps(all_gaps, iqr_signal)
        strip_gaps = classification['strip']

        # --- Define film regions ---
        if not strip_gaps:
            film_regions = [(0, height)]
        else:
            film_regions = []
            prev = 0
            for gs, ge in strip_gaps:
                if gs - prev >= 200:
                    film_regions.append((prev, gs))
                prev = ge
            if height - prev >= 200:
                film_regions.append((prev, height))

        # --- Pass 2: Per-region ratio-based frame detection ---
        for r_start, r_end in film_regions:
            region = strip[r_start:r_end, :]
            region_iqr = _compute_row_iqr(region, sigma=2)

            frame_gaps = _find_gaps_ratio(region_iqr)
            frame_gaps = _merge_gaps(frame_gaps, merge_dist=30)
            frame_gaps = _remove_lone_narrow_gaps(frame_gaps, min_gap_width=8)

            region_global = [(gs, ge) for gs, ge in all_gaps
                           if gs >= r_start and ge <= r_end and (ge - gs) < 200]
            for gg in region_global:
                local_gg = (gg[0] - r_start, gg[1] - r_start)
                if local_gg not in [(g[0], g[1]) for g in frame_gaps]:
                    frame_gaps.append(local_gg)

            frame_gaps.sort(key=lambda g: g[0])
            frame_gaps = _merge_gaps(frame_gaps, merge_dist=30)

            # --- Extract frames ---
            if not frame_gaps:
                all_frames.append({
                    'x': max(0, sx - border_px),
                    'y': max(0, r_start - border_px),
                    'width': min(sw + 2 * border_px, width - max(0, sx - border_px)),
                    'height': min(r_end - r_start + 2 * border_px, height - max(0, r_start - border_px))
                })
                continue

            prev = r_start
            for gs, ge in frame_gaps:
                fy1 = prev
                fy2 = r_start + gs
                if fy2 - fy1 > 200:
                    all_frames.append({
                        'x': max(0, sx - border_px),
                        'y': max(0, fy1 - border_px),
                        'width': min(sw + 2 * border_px, width - max(0, sx - border_px)),
                        'height': min(fy2 - fy1 + 2 * border_px, height - max(0, fy1 - border_px))
                    })
                prev = r_start + ge

            if r_end - prev > 200:
                all_frames.append({
                    'x': max(0, sx - border_px),
                    'y': max(0, prev - border_px),
                    'width': min(sw + 2 * border_px, width - max(0, sx - border_px)),
                    'height': min(r_end - prev + 2 * border_px, height - max(0, prev - border_px))
                })

    # --- Post-processing per strip ---
    for strip_idx, (sx, ex) in enumerate(strips):
        sw = ex - sx
        strip_frames = [f for f in all_frames if abs(f['x'] - (sx - border_px)) < 20]
        other_frames = [f for f in all_frames if f not in strip_frames]
        
        filtered = _filter_frames(strip_frames, sw)
        all_frames = other_frames + filtered

    all_frames.sort(key=lambda r: (r['y'], r['x']))
    for i, f in enumerate(all_frames):
        f['index'] = i
        for k in ('x', 'y', 'width', 'height'):
            f[k] = int(f[k])

    return all_frames


# =======================================================================
# FORMAT-BASED DETECTION
# =======================================================================

# Per-format expected max frames (safety net, not the primary constraint)
_FORMAT_MAX_FRAMES = {
    '135': 12, '135p': 12,
    '645': 5, '66': 5, '67': 4, '68': 4, '69': 4,
    '612': 3, '617': 2, '65x24': 2,
}


def _make_frame(sx: int, sy: int, sw: int, sh: int,
                border_px: int, img_w: int, img_h: int) -> dict:
    """Build a frame dict with border applied, clamped to image bounds."""
    return {
        'x': max(0, sx - border_px),
        'y': max(0, sy - border_px),
        'width': min(sw + 2 * border_px, img_w - max(0, sx - border_px)),
        'height': min(sh + 2 * border_px, img_h - max(0, sy - border_px)),
    }


def _detect_gaps_rowmean(strip: np.ndarray, expected_fh: float) -> list:
    """
    Find inter-frame gaps using row-mean brightness + find_peaks.
    Detects BOTH dark gaps (slide mounts / scanner mask) and bright gaps
    (clear film base in negative scans).
    """
    sh = strip.shape[0]
    row_mean = np.mean(strip, axis=1).astype(np.float64)
    sigma = max(2.0, expected_fh * 0.02)
    row_smooth = gaussian_filter1d(row_mean, sigma=sigma)
    signal_range = float(row_smooth.max() - row_smooth.min())
    if signal_range < 1.0:
        return []

    distance = int(expected_fh * 0.45)
    width_min = max(2, int(expected_fh * 0.002))
    width_max = int(expected_fh * 0.15)
    prominence = signal_range * 0.03  # low threshold → get all candidates

    all_peaks = []

    # -- Dark gaps: invert signal so valleys become peaks --
    inv = row_smooth.max() - row_smooth
    pks, props = find_peaks(
        inv, distance=distance, width=(width_min, width_max),
        prominence=prominence, rel_height=0.5,
    )
    if len(pks) > 0:
        for pk, w in zip(pks, props['widths']):
            all_peaks.append((float(pk), float(w)))

    # -- Bright gaps: use original signal --
    pks2, props2 = find_peaks(
        row_smooth, distance=distance, width=(width_min, width_max),
        prominence=prominence, rel_height=0.5,
    )
    if len(pks2) > 0:
        for pk, w in zip(pks2, props2['widths']):
            all_peaks.append((float(pk), float(w)))

    if not all_peaks:
        return []

    # Convert peaks → gap regions
    all_peaks.sort(key=lambda x: x[0])
    gaps = []
    for pk, w in all_peaks:
        half_w = max(1.0, w / 2.0)
        gs = max(0, int(pk - half_w))
        ge = min(sh, int(pk + half_w))
        gaps.append((gs, ge))

    return _merge_gaps(gaps, merge_dist=max(10, int(expected_fh * 0.02)))


def _iterative_cluster(frames: list, expected_ratio: float,
                       max_hint: int) -> list:
    """
    Try EVERY frame as a potential reference, build a cluster of
    similar-sized frames around it, and pick the best cluster.

    Score = n_frames * 10  -  size_cv * 5  -  ratio_err * 15
    """
    if len(frames) <= 2:
        return frames

    best_cluster = frames
    best_score = -1e9

    for ref in frames:
        ref_a = ref['width'] * ref['height']
        ref_w, ref_h = ref['width'], ref['height']
        if ref_a < 1 or ref_w < 1 or ref_h < 1:
            continue

        cluster = []
        for f in frames:
            a = f['width'] * f['height']
            if not (0.65 < a / ref_a < 1.40):
                continue
            if not (0.70 < f['width'] / ref_w < 1.30):
                continue
            if not (0.65 < f['height'] / ref_h < 1.40):
                continue
            cluster.append(f)

        if len(cluster) < 2:
            continue

        areas = [f['width'] * f['height'] for f in cluster]
        ratios = [f['width'] / max(f['height'], 1) for f in cluster]

        n = len(cluster)
        area_cv = float(np.std(areas)) / (float(np.mean(areas)) + 0.001)
        ratio_err = float(np.mean(
            [abs(r - expected_ratio) / expected_ratio for r in ratios]))

        # Cap the count bonus so a cluster of 40 noise frames doesn't win
        n_bonus = min(n, max_hint + 1)
        score = n_bonus * 10.0 - area_cv * 5.0 - ratio_err * 15.0

        if score > best_score:
            best_score = score
            best_cluster = cluster

    return best_cluster


def detect_frames_with_format(image_array: np.ndarray, format_id: str,
                               border_px: int = 4) -> list:
    """
    Detect frames using a known film format.

    Strategy:
      1. Find vertical strips and compute expected frame size from ratio.
      2. Detect gaps using row-mean brightness (both dark & bright).
      3. Extract candidate frames, validate against expected height & ratio.
      4. ITERATIVE clustering: try every candidate as reference, pick the
         best-scoring cluster — avoids locking onto a single wrong frame.
      5. Final size + count sanity check.
    """
    preset = FORMAT_PRESETS.get(format_id)
    if preset is None:
        return detect_frames(image_array, border_px=border_px)

    expected_ratio = preset['ratio']
    max_hint = _FORMAT_MAX_FRAMES.get(format_id, 20)

    if len(image_array.shape) == 3:
        grayscale = np.mean(image_array.astype(np.float32), axis=2)
    else:
        grayscale = image_array.astype(np.float32)

    img_h, img_w = grayscale.shape
    img_short = min(img_w, img_h)
    strips = _find_strips_via_columns(grayscale) or [(0, img_w)]

    all_frames = []

    for sx, ex in strips:
        strip = grayscale[:, sx:ex]
        sw = ex - sx
        sh = strip.shape[0]
        expected_fh = sw / expected_ratio

        # ---- Step 1: geometric sanity check ----
        # Strip width should be a meaningful fraction of the image short side
        # For 645: frame long-side (sw) ≥ 0.4 × image short side
        # For 67:  frame short-side (expected_fh) ≥ 0.4 × image short side
        if format_id in ('645', '66', '68'):
            if sw < img_short * 0.35:
                continue  # strip too narrow for this format
        elif format_id in ('67', '69', '612', '617'):
            if expected_fh < img_short * 0.35:
                continue

        # ---- Step 2: find gaps via row-mean ----
        gap_regions = _detect_gaps_rowmean(strip, expected_fh)

        # ---- Step 3: extract candidate frames ----
        if not gap_regions:
            if sh >= expected_fh * 0.50:
                all_frames.append(
                    _make_frame(sx, 0, sw, sh, border_px, img_w, img_h))
            continue

        # First frame (top → first gap)
        fh = gap_regions[0][0]
        if fh >= expected_fh * 0.50:
            all_frames.append(
                _make_frame(sx, 0, sw, fh, border_px, img_w, img_h))

        # Middle frames
        for i in range(len(gap_regions) - 1):
            fy1 = gap_regions[i][1]
            fy2 = gap_regions[i + 1][0]
            fh = fy2 - fy1
            if fh >= expected_fh * 0.50:
                all_frames.append(
                    _make_frame(sx, fy1, sw, fh, border_px, img_w, img_h))

        # Last frame
        fh = sh - gap_regions[-1][1]
        if fh >= expected_fh * 0.50:
            all_frames.append(
                _make_frame(sx, gap_regions[-1][1], sw, fh, border_px,
                            img_w, img_h))

    # ---- Step 4: iterative clustering ----
    if not all_frames:
        debug_log(
            f"[DETECT:{format_id}] no frames extracted, falling back to auto")
        return detect_frames(image_array, border_px=border_px)

    # Pre-filter: ratio must be roughly correct
    ratio_ok = []
    for fr in all_frames:
        ar = fr['width'] / max(fr['height'], 1)
        if abs(ar - expected_ratio) / expected_ratio < 0.40:
            ratio_ok.append(fr)

    sx, ex = strips[0] if strips else (0, img_w)
    sw_log = ex - sx
    efh_log = sw_log / expected_ratio
    debug_log(
        f"[DETECT:{format_id}] sw={sw_log} img={img_w}x{img_h} "
        f"expected_fh={efh_log:.0f} candidates={len(all_frames)} "
        f"ratio_ok={len(ratio_ok)}"
    )

    if not ratio_ok:
        debug_log(
            f"[DETECT:{format_id}] nothing matches ratio, "
            "falling back to auto"
        )
        return detect_frames(image_array, border_px=border_px)

    # Iterative clustering: try every frame as reference
    valid = _iterative_cluster(ratio_ok, expected_ratio, max_hint)

    # ---- Step 5: final safety net ----
    if len(valid) > max_hint:
        # Sort by how close area is to median, keep best N
        areas = np.array([f['width'] * f['height'] for f in valid])
        median_a = np.median(areas)
        scored = [(abs(a - median_a), f) for a, f in zip(areas, valid)]
        scored.sort(key=lambda x: x[0])
        valid = [f for _, f in scored[:max_hint]]

    valid.sort(key=lambda r: (r['y'], r['x']))
    for i, fr in enumerate(valid):
        fr['index'] = i
        for k in ('x', 'y', 'width', 'height'):
            fr[k] = int(fr[k])

    debug_log(
        f"[DETECT:{format_id}] final={len(valid)} frames | "
        f"sizes={[(fr['width'], fr['height']) for fr in valid]}"
    )

    return valid


# =======================================================================
# AUTO FORMAT DETECTION
# =======================================================================

def guess_format(image_array: np.ndarray) -> str:
    """
    Guess the film format from image geometry.

    Heuristics:
      - 135 (35mm): two film strips placed one above the other.
        Each strip occupies 25–50 % of total image height.
      - 120 (medium format): single strip filling most of the image.
        The specific sub-format (645/66/67/etc.) is inferred from
        the detected frame aspect ratios.

    Returns a format ID string: '135', '645', '66', '67', '68', '69',
    '612', '617', or 'auto' if uncertain.
    """
    if len(image_array.shape) == 3:
        grayscale = np.mean(image_array.astype(np.float32), axis=2)
    else:
        grayscale = image_array.astype(np.float32)

    height, width = grayscale.shape

    # -- Step 1: find strips and global gaps --
    strips = _find_strips_via_columns(grayscale) or [(0, width)]

    # Row IQR on the first (or only) strip
    sx, ex = strips[0]
    strip = grayscale[:, sx:ex]
    iqr_signal = _compute_row_iqr(strip, sigma=3)

    all_gaps = _find_gaps_global(iqr_signal)
    all_gaps = _merge_gaps(all_gaps, merge_dist=50)

    classification = _classify_gaps(all_gaps, iqr_signal)
    strip_gaps = classification['strip']

    # -- Step 2: check for 135-like double-strip pattern --
    # Each film region should be 25–50 % of total height
    if strip_gaps:
        regions = []
        prev = 0
        for gs, ge in strip_gaps:
            if gs - prev >= 200:
                regions.append((prev, gs))
            prev = ge
        if height - prev >= 200:
            regions.append((prev, height))

        region_heights = [re - rs for rs, re in regions]
        if len(regions) >= 2:
            # Check if each region is roughly 25-50% of total → 135 pattern
            ratios = [rh / height for rh in region_heights]
            if all(0.22 < r < 0.52 for r in ratios[:2]):
                return '135'

    # -- Step 3: it's 120 → guess sub-format from frame aspect ratios --
    # Run a quick auto-detect to get candidate frames
    auto_frames = detect_frames(image_array, border_px=4)
    if not auto_frames or len(auto_frames) < 2:
        return 'auto'

    # Compute median frame aspect ratio
    ratios = []
    for f in auto_frames:
        ar = f['width'] / max(f['height'], 1)
        if 0.5 < ar < 4.0:
            ratios.append(ar)

    if not ratios:
        return 'auto'

    median_ar = float(np.median(ratios))

    # Compare against known 120 format ratios
    # Ordered from most common
    candidates = [
        ('66',  1.0),
        ('67',  7/6),
        ('645', 4/3),
        ('68',  8/6),
        ('69',  9/6),
        ('612', 12/6),
        ('617', 17/6),
        ('65x24', 65/24),
    ]

    best, best_err = 'auto', 999.0
    for fmt_id, fmt_ratio in candidates:
        err = abs(median_ar - fmt_ratio) / fmt_ratio
        if err < best_err:
            best_err = err
            best = fmt_id

    if best_err < 0.25:
        return best
    return 'auto'
