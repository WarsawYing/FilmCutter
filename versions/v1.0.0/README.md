# FilmCutter Ver.1 — archived documentation

Status: **Archived**
Suggested source tag: `v1.0.0`

This page preserves the public documentation from the original FilmCutter
release before the 1.01 Beta update. It is retained for historical reference;
new users should start from the [current repository homepage](../../README.md).

## Original description

FilmCutter is a macOS app for cutting scanned film strips into individual
frames. It was designed for Hasselblad X5 scanner TIFF output and supported:

- TIFF input (8-bit and 16-bit, grayscale or RGB)
- automatic frame detection with multi-stage signal analysis
- batch processing for multiple film strips in one scan
- negative inversion
- uncompressed 16-bit TIFF output
- smart naming such as `BATCHNAME_001.tif`

## Original detector design

Ver.1 exposed two selectable detectors:

- **V2 — Constrained**, used by default for Auto/135 scans.
- **Classic**, retained as a rollback and comparison path.

V2 opened large TIFFs through a memory map, generated an area-sampled
thumbnail, found horizontal or vertical film strips and mapped its rectangles
back to source coordinates. Other formats could still fall back to Classic.

## Original workflow

1. Launch the app.
2. Drag in a TIFF file or choose it with the file picker.
3. Review, move, resize, add, delete, undo, redo or reset detected frames.
4. Configure border, negative inversion, batch name and output folder.
5. Cut and export numbered, uncompressed TIFF files.

Existing output files were never overwritten. Source bit depth, ICC profile
and scan resolution were preserved during export.

## Original development requirements

- macOS 14 or later
- Apple Silicon
- Python 3.9+
- NumPy, Pillow, SciPy and tifffile
- Xcode 15 or Swift 5.9 for local builds

These requirements applied to Ver.1 development and are not the requirements
for 1.01 Beta users. The current Beta download includes its own reduced runtime.

## Original limitations

- Multi-page TIFF files were rejected.
- V2 primarily covered Auto/135/135p.
- Other film formats could use the Classic detector while their V2 constraints
  were still under development.

The exact Ver.1 source remains available from the repository history and its
archival source tag once published.
