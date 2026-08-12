# FilmCutter 1.01 Beta

Git tag: [`v1.0.1-beta.1`](https://github.com/WarsawYing/FilmCutter/tree/v1.0.1-beta.1)

Status: **Pre-release**

Author: Warsawying

Copyright © 2026 Warsawying

## Download

**[FilmCutter-1.01-Beta-macOS-Apple-Silicon.zip](https://github.com/WarsawYing/FilmCutter/releases/download/v1.0.1-beta.1/FilmCutter-1.01-Beta-macOS-Apple-Silicon.zip)**

Requirements: Apple Silicon and macOS 14 or later. The download is
self-contained and works offline; end users do not install Python or any
package manager.

- [Installation and upgrade guide](INSTALL.md)
- [SHA-256 checksum](SHA256SUMS)
- [Repository homepage](../../README.md)

## Highlights

- Five-language interface with immediate, persistent switching.
- Back-and-forth import, adjustment and export confirmation workflow.
- Per-scan film format, expected frame count, manual edits and undo history.
- V2-only detection for the complete published format list.
- Experimental boundary refinement that automatically returns to stable V2
  whenever count, order, geometry or score becomes worse.
- Unicode-safe naming, natural sorting, complete collision checks and atomic
  no-overwrite export.
- Embedded Apple Silicon CPython 3.13.15 with only NumPy and tifffile.

## Validation

- Python regression suite: **26 passed**.
- Swift/XCTest suite: **10 passed**.
- Available real 135 positive and negative scans: count and order passed.
- Installer smoke tests: first install, upgrade and failed-copy rollback passed.
- Bundle checks: arm64, ad-hoc signature, embedded imports, no development path,
  no pip and no Homebrew/system-Python dependency passed.
- Release ZIP size: **24,450,887 bytes** (well below 70 MiB).

## Beta limitations

- Input is limited to uncompressed, single-page 8/16-bit grayscale or RGB TIFF.
- Real-scan validation currently covers available 135 fixtures. Other published
  formats remain Beta until the documented real-scan and IoU gates are complete.
- This build uses an ad-hoc signature. Formal 1.1 requires Developer ID signing,
  notarization and stapling.

## Package contents

The ZIP contains:

- `FilmCutter.app`
- `安装 FilmCutter.command`
- five-language quick installation instructions
- `CHECKSUMS.txt`
- AGPL-3.0 license and third-party notices

The ZIP is stored as a GitHub Release asset, not committed to Git history.
