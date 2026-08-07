#!/usr/bin/env python3
"""
FilmCutter Python Engine
Main entry point that communicates with the Swift frontend via JSON over stdin/stdout.

Commands:
  get_info  - Get info about a list of files
  detect    - Detect frames in a single file
  preview   - Detect frames and return low-res preview (base64 JPEG) for one or more files
  process   - Cut frames from one or more files
  ping      - Ping
  exit      - Exit
"""

import sys
import json
import os
import traceback
import io
import base64

# Add the PythonEngine directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from image_reader import read_image, get_image_info
from frame_detector import detect_frames, detect_frames_with_format
from detectors.v2 import detect_file_v2
from processor import cut_frames, save_frame_as_tiff, get_output_filename
from debug_log import debug_log
import numpy as np


def send_response(response: dict):
    """Send a JSON response to stdout."""
    print(json.dumps(response), flush=True)


def handle_get_info(data: dict) -> dict:
    """Handle 'get_info' command - get info about a list of files."""
    files = data.get('files', [])
    results = []
    
    for filepath in files:
        try:
            info = get_image_info(filepath)
            results.append(info)
        except Exception as e:
            results.append({
                'filename': os.path.basename(filepath),
                'filepath': filepath,
                'error': str(e)
            })
    
    return {'status': 'ok', 'files': results}


def handle_detect(data: dict) -> dict:
    """
    Handle 'detect' command - detect frames in a single file.
    Kept for backward compatibility.
    """
    filepath = data.get('file', '')
    border_px = data.get('border_px', 4)
    
    try:
        image_array, metadata = read_image(filepath)
        frames = detect_frames(image_array, border_px=border_px)
        
        return {
            'status': 'ok',
            'filename': os.path.basename(filepath),
            'width': metadata['width'],
            'height': metadata['height'],
            'bit_depth': metadata['bit_depth'],
            'frames': [{
                'index': f['index'],
                'x': f['x'],
                'y': f['y'],
                'width': f['width'],
                'height': f['height']
            } for f in frames],
            'frame_count': len(frames)
        }
    except Exception as e:
        return {
            'status': 'error',
            'file': filepath,
            'error': str(e),
            'traceback': traceback.format_exc()
        }


def _generate_preview(image_array: np.ndarray, metadata: dict,
                      frames: list, max_width: int = 400) -> dict:
    """
    Generate a low-res JPEG preview with frame rectangles drawn on it.
    Downsamples first to avoid processing the full-resolution image.
    Returns dict with preview_b64 (base64 JPEG string) and metadata.
    """
    from PIL import Image as PILImage

    h, w = image_array.shape[:2]
    scale = max_width / w if w > max_width else 1.0
    preview_w = int(w * scale)
    preview_h = int(h * scale)

    # Step 1: Strided subsample to ~2× target size (drastic memory reduction)
    step = max(1, int(w / (max_width * 2)))
    if len(image_array.shape) == 3:
        sub = image_array[::step, ::step, :]
    else:
        sub = image_array[::step, ::step]

    # Step 2: Percentile contrast stretch on the small array
    flat = sub.ravel()
    p1 = max(np.percentile(flat, 1), 0)
    data_max = 65535 if sub.dtype == np.uint16 or sub.max() > 255 else 255
    p99 = min(np.percentile(flat, 99), data_max)
    range_val = max(p99 - p1, 1)

    norm = ((sub.astype(np.float32) - p1) / range_val * 255)
    norm = norm.clip(0, 255).astype(np.uint8)

    if len(norm.shape) == 3:
        img = PILImage.fromarray(norm)
    else:
        img = PILImage.fromarray(norm)

    # Step 3: Resize to exact preview dimensions
    img = img.resize((preview_w, preview_h), PILImage.LANCZOS)

    # Step 4: Encode as JPEG (frames are drawn by SwiftUI overlay)
    buf = io.BytesIO()
    img.save(buf, format='JPEG', quality=75)
    b64_str = base64.b64encode(buf.getvalue()).decode('utf-8')

    return {
        'preview_b64': b64_str,
        'width': w,
        'height': h,
        'preview_width': preview_w,
        'preview_height': preview_h,
    }


def handle_preview(data: dict) -> dict:
    """
    Handle 'preview' command - detect frames and generate low-res preview
    for one or more files. Supports format-based detection.
    
    Input:
      files: [str]  - list of file paths
      format: str   - format identifier (auto, 135, 645, 66, 67, etc.)
      border_px: int
    
    Output:
      status: str
      data: [{
        file_path, file_name, width, height, bit_depth,
        estimated_format, frames: [...], preview_b64: str
      }]
    """
    files = data.get('files', [])
    if not files:
        files = [data.get('file', '')] if data.get('file') else []
    if not files:
        return {'status': 'error', 'message': 'No files provided'}
    
    format_id = data.get('format', 'auto')
    detector_id = data.get('detector', 'v2')

    results = []
    errors = []
    total = len(files)
    
    for idx, filepath in enumerate(files):
        # Send progress before processing each file
        send_response({
            'status': 'progress',
            'progress': idx / max(total, 1),
            'message': f'File {idx + 1}/{total}: {os.path.basename(filepath)}...'
        })
        try:
            # Detector V2 owns its complete file-based preview path.  This is
            # important: calling read_image first would decode a 600+ MB TIFF
            # into RAM before V2 had a chance to build its small thumbnail.
            if (
                detector_id == 'v2'
                and format_id in ('auto', '135', '135p')
            ):
                detected = detect_file_v2(filepath, format_id=format_id)
                results.append({
                    'file_path': filepath,
                    'file_name': detected['file_name'],
                    'width': detected['width'],
                    'height': detected['height'],
                    'bit_depth': detected['bit_depth'],
                    'estimated_format': detected['estimated_format'],
                    'frames': detected['frames'],
                    'frame_count': detected['frame_count'],
                    'preview_b64': detected['preview_b64'],
                    'detector': detected['detector'],
                    'strip_count': detected['strip_count'],
                })
                continue

            image_array, metadata = read_image(filepath)
            
            # Preview rectangles represent content only. User-selected padding
            # is applied once, at export time, by processor.cut_frames.
            if format_id and format_id != 'auto':
                frames = detect_frames_with_format(
                    image_array, format_id=format_id, border_px=0
                )
            else:
                # Plain auto-detect — no format guessing on initial load.
                # Format-aware detection runs when user explicitly picks
                # a format and clicks Update.
                frames = detect_frames(image_array, border_px=0)
            
            # Generate preview image with frame overlays
            preview_data = _generate_preview(image_array, metadata, frames)
            
            result = {
                'file_path': filepath,
                'file_name': metadata['filename'],
                'width': metadata['width'],
                'height': metadata['height'],
                'bit_depth': metadata['bit_depth'],
                'estimated_format': format_id if format_id != 'auto' else 'auto',
                'frames': [{
                    'index': f['index'],
                    'x': f['x'],
                    'y': f['y'],
                    'width': f['width'],
                    'height': f['height']
                } for f in frames],
                'frame_count': len(frames),
                'preview_b64': preview_data['preview_b64'],
                'detector': 'classic',
            }
            results.append(result)
            
        except Exception as e:
            errors.append(f"{os.path.basename(filepath)}: {e}")
            results.append({
                'file_path': filepath,
                'file_name': os.path.basename(filepath),
                'error': str(e),
                'status': 'error',
            })
    
    send_response({
        'status': 'progress',
        'progress': 1.0,
        'message': 'Generating preview complete.'
    })
    if errors:
        return {
            'status': 'error',
            'error_code': 'ERR_0007',
            'message': f"{len(errors)} file(s) could not be loaded: " + "; ".join(errors),
            'data': results,
        }
    return {'status': 'ok', 'data': results}


def handle_process(data: dict) -> dict:
    """
    Handle 'process' command - cut frames from one or more files.
    Supports both single file (with frames list) and batch (with files list).
    
    New combined_frames param: a list of lists, each sub-list is the frame list
    for the corresponding file in the files list.
    """
    files = data.get('files', [])
    single_file = data.get('file')
    output_dir = data.get('output_dir', '')
    batch_name = data.get('batch_name', 'Film')
    invert = data.get('invert', False)
    border_px = data.get('border_px', 4)
    combined_frames = data.get('combined_frames', None)

    # Parse roll metadata from Swift JSON (camelCase → snake_case)
    swift_meta = data.get('metadata', {}) or {}
    roll_meta = {
        'camera': swift_meta.get('camera', ''),
        'lens': swift_meta.get('lens', ''),
        'aperture': swift_meta.get('aperture', ''),
        'film_stock': swift_meta.get('filmStock', ''),
        'push_pull': swift_meta.get('pushPull', 'None'),
        'date': swift_meta.get('date', ''),
        'scanner': swift_meta.get('scanner', ''),
        'notes': swift_meta.get('notes', ''),
    }

    frame_counter = 0
    all_output_files = []

    try:
        if combined_frames is not None and files:
            # The lists are positional: frames[i] must always belong to files[i].
            # Reject malformed requests instead of silently cutting the wrong scan.
            if len(combined_frames) != len(files):
                raise ValueError(
                    "files and combined_frames must have the same length")
            expected_count = sum(len(frame_list) for frame_list in combined_frames)
            if expected_count == 0:
                raise ValueError("No frames were provided for processing")
            _ensure_output_paths_available(output_dir, batch_name, expected_count)
            # New combined processing: each file has its own frame list
            for idx, filepath in enumerate(files):
                send_response({
                    'status': 'progress',
                    'progress': idx / max(len(files), 1),
                    'message': f'Cutting file {idx + 1}/{len(files)}: {os.path.basename(filepath)}',
                })
                image_array, metadata = read_image(
                    filepath, memory_mapped=True)
                debug_log(
                    f"[READ] file={filepath} shape={image_array.shape} "
                    f"dtype={image_array.dtype}"
                )
                frames_for_file = combined_frames[idx]

                # Crop and save one frame at a time. Keeping all 12 RGB16
                # crops in a list can consume more RAM than the source scan.
                for frame in frames_for_file:
                    cut = cut_frames(image_array, [{
                        'x': frame['x'], 'y': frame['y'],
                        'width': frame['width'], 'height': frame['height']
                    }], metadata, convert=invert, border_px=border_px)
                    output_files = _save_cut_frames(
                        cut,
                        output_dir,
                        batch_name,
                        frame_counter,
                        roll_metadata=roll_meta,
                    )
                    all_output_files.extend(output_files)
                    frame_counter += 1
        elif single_file and data.get('frames'):
            _ensure_output_paths_available(
                output_dir, batch_name, len(data['frames']))
            send_response({
                'status': 'progress',
                'progress': 0.0,
                'message': f'Cutting {os.path.basename(single_file)}',
            })
            # Traditional single-file processing
            image_array, metadata = read_image(
                single_file, memory_mapped=True)
            frame_list = [{
                'x': f['x'] if isinstance(f, dict) else f.x,
                'y': f['y'] if isinstance(f, dict) else f.y,
                'width': f['width'] if isinstance(f, dict) else f.width,
                'height': f['height'] if isinstance(f, dict) else f.height,
            } for f in data['frames']]
            
            for frame in frame_list:
                cut = cut_frames(
                    image_array,
                    [frame],
                    metadata,
                    convert=invert,
                    border_px=border_px,
                )
                output_files = _save_cut_frames(
                    cut,
                    output_dir,
                    batch_name,
                    frame_counter,
                    roll_metadata=roll_meta,
                )
                all_output_files.extend(output_files)
                frame_counter += 1
        elif files and combined_frames is None:
            # Legacy batch processing: detect per file
            for idx, filepath in enumerate(files):
                send_response({
                    'status': 'progress',
                    'progress': idx / max(len(files), 1),
                    'message': f'Cutting file {idx + 1}/{len(files)}: {os.path.basename(filepath)}',
                })
                image_array, metadata = read_image(filepath)
                
                frames = detect_frames(image_array, border_px=0)
                for frame in frames:
                    cut = cut_frames(
                        image_array,
                        [frame],
                        metadata,
                        convert=invert,
                        border_px=border_px,
                    )
                    output_files = _save_cut_frames(
                        cut,
                        output_dir,
                        batch_name,
                        frame_counter,
                        roll_metadata=roll_meta,
                    )
                    all_output_files.extend(output_files)
                    frame_counter += 1
        else:
            return {
                'status': 'error',
                'error_code': 'ERR_0008',
                'message': 'No files or frames provided',
            }

        send_response({
            'status': 'progress',
            'progress': 1.0,
            'message': 'Finished writing TIFF files.',
        })

        return {
            'status': 'complete',
            'message': f'Successfully cut {len(all_output_files)} frames',
            'files': all_output_files,
            'frame_count': len(all_output_files),
            'results': [{'output_files': [{'output_path': f}] for f in all_output_files}],
        }

    except Exception as e:
        # A batch is all-or-nothing. If a later source fails, remove outputs
        # created earlier in this request so the folder never looks complete.
        for output_path in reversed(all_output_files):
            try:
                os.unlink(output_path)
            except FileNotFoundError:
                pass
        return {
            'status': 'error',
            'error_code': 'ERR_0009',
            'error': str(e),
            'traceback': traceback.format_exc()
        }


def _ensure_output_paths_available(output_dir: str, batch_name: str,
                                   frame_count: int):
    """Refuse to overwrite any existing output file."""
    if not output_dir:
        raise ValueError("Output directory is required")
    collisions = []
    for index in range(1, frame_count + 1):
        path = os.path.join(output_dir, get_output_filename(batch_name, index))
        if os.path.exists(path):
            collisions.append(path)
    if collisions:
        names = ", ".join(os.path.basename(path) for path in collisions[:3])
        suffix = "…" if len(collisions) > 3 else ""
        raise FileExistsError(
            f"Output already exists ({names}{suffix}). "
            "Choose another roll name or output folder."
        )


def _save_cut_frames(cut_results: list, output_dir: str,
                     batch_name: str, start_index: int,
                     roll_metadata: dict = None) -> list:
    """Save cut frames to disk with sequential numbering and metadata."""
    output_files = []
    try:
        for i, frame_result in enumerate(cut_results):
            filename = get_output_filename(batch_name, start_index + i + 1)
            output_path = os.path.join(output_dir, filename)
            save_frame_as_tiff(
                frame_result['data'],
                output_path,
                roll_metadata=roll_metadata,
                source_metadata=frame_result.get('source_metadata'),
            )
            output_files.append(output_path)
    except Exception:
        # Roll back files written by this group; the outer handler rolls back
        # groups that completed earlier in the same batch.
        for output_path in reversed(output_files):
            try:
                os.unlink(output_path)
            except FileNotFoundError:
                pass
        raise
    return output_files


def main():
    """Main entry point. Reads JSON commands from stdin, sends responses to stdout."""
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            data = json.loads(line)
            command = data.get('command', '')
            
            if command == 'get_info':
                response = handle_get_info(data)
            elif command == 'detect':
                response = handle_detect(data)
            elif command == 'preview':
                response = handle_preview(data)
            elif command == 'process':
                response = handle_process(data)
            elif command == 'ping':
                response = {'status': 'ok', 'message': 'pong'}
            elif command == 'exit':
                send_response({'status': 'ok', 'message': 'exiting'})
                break
            else:
                response = {'status': 'error', 'error': f'Unknown command: {command}'}
            
            send_response(response)
            
        except json.JSONDecodeError as e:
            send_response({'status': 'error', 'error': f'Invalid JSON: {e}'})
        except Exception as e:
            send_response({'status': 'error', 'error': str(e), 'traceback': traceback.format_exc()})


if __name__ == '__main__':
    main()
