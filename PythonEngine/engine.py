#!/usr/bin/env python3
"""FilmCutter V2 JSON engine.

All user-facing text is represented by stable codes and optional arguments so
the Swift app can localize it.  The engine only reads/writes local TIFF files.
"""

from __future__ import annotations

import json
import os
import sys
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from debug_log import debug_log
from detectors.v2 import detect_file_v2
from image_reader import get_image_info, read_image
from processor import cut_frames, get_output_filename, save_frame_as_tiff


def send_response(response: dict):
    print(json.dumps(response), flush=True)


def _error(code: str, detail: str = "", **extra) -> dict:
    response = {"status": "error", "error_code": code}
    # Details stay in opt-in diagnostic logs. The Swift protocol receives only
    # stable codes and structured arguments so user-facing text is localized.
    if detail:
        debug_log(f"[{code}] {detail}")
    response.update(extra)
    return response


def handle_get_info(data: dict) -> dict:
    results = []
    for filepath in data.get("files", []):
        try:
            results.append(get_image_info(filepath))
        except Exception as exc:
            results.append({
                "filename": os.path.basename(filepath),
                "filepath": filepath,
                "status": "error",
                "error_code": "ERR_TIFF_READ",
                "error_args": [os.path.basename(filepath)],
            })
    return {"status": "ok", "files": results}


def handle_preview(data: dict) -> dict:
    files = data.get("files", [])
    if not files and data.get("file"):
        files = [data["file"]]
    if not files:
        return _error("ERR_NO_INPUT")

    format_id = data.get("format_id", data.get("format", "auto"))
    expected_count = data.get("expected_count")
    refine_contour = bool(data.get("refine_contour", False))
    results, failures = [], []
    total = len(files)
    for index, filepath in enumerate(files):
        send_response({
            "status": "progress",
            "progress": index / max(total, 1),
            "message_code": "PROGRESS_PREVIEW_FILE",
            "message_args": [index + 1, total, os.path.basename(filepath)],
        })
        try:
            detected = detect_file_v2(
                filepath,
                format_id=format_id,
                expected_count=expected_count,
                refine_contour=refine_contour,
            )
            results.append({
                "file_path": filepath,
                "file_name": detected["file_name"],
                "width": detected["width"],
                "height": detected["height"],
                "bit_depth": detected["bit_depth"],
                "estimated_format": detected["estimated_format"],
                "selected_format": detected["selected_format"],
                "frames": detected["frames"],
                "frame_count": detected["frame_count"],
                "found_count": detected["found_count"],
                "expected_count": detected["expected_count"],
                "preview_b64": detected["preview_b64"],
                "detector": "v2",
                "strip_count": detected["strip_count"],
                "refinement_applied": detected["refinement_applied"],
                "refinement_fallback_reason": detected["refinement_fallback_reason"],
            })
        except Exception as exc:
            failures.append(filepath)
            results.append({
                "file_path": filepath,
                "file_name": os.path.basename(filepath),
                "status": "error",
                "error_code": "ERR_PREVIEW_FILE",
                "error_args": [os.path.basename(filepath)],
            })

    send_response({
        "status": "progress",
        "progress": 1.0,
        "message_code": "PROGRESS_PREVIEW_COMPLETE",
        "message_args": [],
    })
    if failures:
        return _error(
            "ERR_PREVIEW_PARTIAL",
            f"{len(failures)} file(s) could not be loaded",
            data=results,
            error_args=[len(failures)],
        )
    return {"status": "ok", "data": results}


def validate_output_paths(output_dir: str, batch_name: str,
                          frame_count: int) -> dict:
    if not output_dir:
        return _error("ERR_OUTPUT_REQUIRED", "Output directory is required")
    filenames = [get_output_filename(batch_name, index)
                 for index in range(1, frame_count + 1)]
    collisions = [name for name in filenames
                  if os.path.exists(os.path.join(output_dir, name))]
    if collisions:
        return _error(
            "ERR_OUTPUT_COLLISION",
            "Output already exists. Choose another roll name or output folder.",
            collisions=collisions,
        )
    return {"status": "ok", "filenames": filenames}


def handle_validate_output(data: dict) -> dict:
    try:
        frame_count = int(data.get("frame_count", 0))
    except (TypeError, ValueError):
        return _error("ERR_INVALID_FRAME_COUNT")
    if frame_count < 1:
        return _error("ERR_NO_FRAMES")
    return validate_output_paths(
        data.get("output_dir", ""), data.get("batch_name", ""), frame_count)


def _swift_metadata(data: dict) -> dict:
    source = data.get("metadata", {}) or {}
    return {
        "camera": source.get("camera", ""),
        "lens": source.get("lens", ""),
        "aperture": source.get("aperture", ""),
        "film_stock": source.get("filmStock", ""),
        "push_pull": source.get("pushPull", "None"),
        "date": source.get("date", ""),
        "scanner": source.get("scanner", ""),
        "notes": source.get("notes", ""),
    }


def handle_process(data: dict) -> dict:
    files = data.get("files", [])
    combined_frames = data.get("combined_frames")
    output_dir = data.get("output_dir", "")
    batch_name = data.get("batch_name", "")
    invert = bool(data.get("invert", False))
    border_px = int(data.get("border_px", 4))
    metadata = _swift_metadata(data)
    created: list[str] = []

    try:
        # Compatibility with the old one-file wire shape, without restoring
        # legacy automatic detection or the Classic detector.
        if combined_frames is None and data.get("file") and data.get("frames"):
            files = [data["file"]]
            combined_frames = [data["frames"]]
        if not files or combined_frames is None:
            return _error("ERR_NO_INPUT")
        if len(files) != len(combined_frames):
            return _error(
                "ERR_BATCH_ALIGNMENT",
                "files and combined_frames must have the same length")
        frame_count = sum(len(frames) for frames in combined_frames)
        validation = validate_output_paths(output_dir, batch_name, frame_count)
        if validation["status"] != "ok":
            return validation

        counter = 0
        for file_index, (filepath, frames) in enumerate(zip(files, combined_frames)):
            send_response({
                "status": "progress",
                "progress": file_index / max(len(files), 1),
                "message_code": "PROGRESS_PROCESS_FILE",
                "message_args": [file_index + 1, len(files), os.path.basename(filepath)],
            })
            image, source_metadata = read_image(filepath, memory_mapped=True)
            debug_log(f"[READ] file={filepath} shape={image.shape} dtype={image.dtype}")
            for frame in frames:
                cut = cut_frames(image, [{
                    "x": frame["x"], "y": frame["y"],
                    "width": frame["width"], "height": frame["height"],
                }], source_metadata, convert=invert, border_px=border_px)[0]
                output_path = os.path.join(
                    output_dir, get_output_filename(batch_name, counter + 1))
                save_frame_as_tiff(
                    cut["data"], output_path, roll_metadata=metadata,
                    source_metadata=cut.get("source_metadata"))
                created.append(output_path)
                counter += 1

        send_response({
            "status": "progress", "progress": 1.0,
            "message_code": "PROGRESS_PROCESS_COMPLETE", "message_args": [],
        })
        return {
            "status": "complete",
            "message_code": "PROCESS_COMPLETE",
            "message_args": [len(created)],
            "files": created,
            "frame_count": len(created),
        }
    except Exception as exc:
        for output_path in reversed(created):
            try:
                os.unlink(output_path)
            except FileNotFoundError:
                pass
        debug_log(traceback.format_exc())
        return _error("ERR_PROCESS", str(exc))


def dispatch(data: dict) -> dict:
    command = data.get("command", "")
    if command == "get_info":
        return handle_get_info(data)
    if command == "preview":
        return handle_preview(data)
    if command == "validate_output":
        return handle_validate_output(data)
    if command == "process":
        return handle_process(data)
    if command == "ping":
        return {"status": "ok", "message_code": "PONG"}
    return _error("ERR_UNKNOWN_COMMAND", command)


def main():
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            data = json.loads(line)
            if data.get("command") == "exit":
                send_response({"status": "ok", "message_code": "EXITING"})
                break
            send_response(dispatch(data))
        except json.JSONDecodeError as exc:
            send_response(_error("ERR_INVALID_JSON", str(exc)))
        except Exception as exc:
            debug_log(traceback.format_exc())
            send_response(_error("ERR_ENGINE", str(exc)))


if __name__ == "__main__":
    main()
