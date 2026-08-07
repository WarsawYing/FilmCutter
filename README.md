# FilmCutter

A macOS app for cutting scanned film strips into individual frames.

Designed for Hasselblad X5 scanner output (TIFF files). Supports:
- **TIFF** (8-bit and 16-bit, grayscale or RGB)
- **Auto frame detection** with multi-stage signal analysis
- **Batch processing** for multiple film strips in one scan
- **Film negative inversion** (invert colors for negatives)
- **Uncompressed TIFF output** (preserving 16-bit depth)
- **Smart naming**: `BATCHNAME_001.tif`, `BATCHNAME_002.tif`, etc.

## Architecture

```
FilmCutter/
├── PythonEngine/           # Python processing engine
│   ├── requirements.txt    # Python dependencies
│   ├── image_reader.py     # TIFF image reading
│   ├── frame_detector.py   # Classic detector (kept for rollback)
│   ├── detectors/v2/       # Memory-bounded, constrained detector
│   ├── processor.py        # Frame cutting + export
│   └── engine.py           # JSON-RPC stdin/stdout engine
│
└── FilmCutterApp/          # Swift macOS app
    └── Sources/
        ├── FilmCutterApp.swift
        ├── ContentView.swift
        ├── Core/
        │   ├── Models.swift
        │   └── PythonBridge.swift
        └── Resources/
            └── Info.plist
```

## Frame Detection Algorithms

The app exposes two selectable detectors:

- **V2 — Constrained** (default for auto/135): opens large TIFFs through a
  memory map, builds an area-sampled thumbnail, finds horizontal or vertical
  textured film strips, applies repeated 135 geometry, and rejects blank film
  tails instead of filling a target count.
- **Classic**: the original projection/IQR detector, retained as an immediate
  rollback and comparison baseline.

V2 maps rectangles back with independent X/Y scale factors. Original 16-bit
pixels are only used during final export.

## Building

### Prerequisites
- macOS 14+ (Sonoma)
- Python 3.9+
- Xcode 15+ (or Swift 5.9+ CLI tools)

### Python Setup
```bash
./setup.sh
```

The setup script creates and validates an isolated Python environment, installs
the pinned image-processing dependencies, and builds the Swift application.

### Run
```bash
cd FilmCutterApp
swift run
```

### Test
```bash
PythonEngine/venv/bin/python3 PythonEngine/test_engine.py
```

## Usage

1. Launch the app
2. Drag & drop a scanned TIFF file (or use file picker)
3. Review detected frames in the right panel. Frames can be moved, resized,
   added, deleted, undone, redone, or reset to the last automatic baseline.
4. Configure:
   - **Border**: Extra pixels around each frame (3-5 recommended)
   - **Invert**: Check for film negatives
   - **Batch Name**: Prefix for output files
   - **Output**: Choose destination folder
5. Click "Cut N Frames"
6. Output: Uncompressed TIFF files. Existing output files are never overwritten.

## Features

- **Drop zone**: Simple drag-and-drop file input
- **Auto detection**: Handles 135 (35mm) and 120 (medium format) films
- **Safe manual correction**: A zero-frame result still opens for editing;
  re-detection asks before replacing manual changes
- **Multi-strip**: Detects and processes multiple columns of frames
- **16-bit**: Preserves full bit depth throughout processing
- **Color managed**: Preserves source ICC profile and scan resolution
- **Lossless**: Uncompressed TIFF output

## Requirements

- Python 3.9+ with numpy, Pillow, scipy, and tifffile
- macOS 14+ (Apple Silicon/M-series)

## Current Limitations

- Multi-page TIFF files are rejected rather than silently processing only the
  first page. Split them into one TIFF per scan before importing.
- Detector V2 currently uses its new constrained path for auto/135/135p.
  Other film formats continue to use the Classic detector while their V2
  constraints are developed and tested.
