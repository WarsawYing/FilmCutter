# FilmCutter 1.1 release candidate

FilmCutter 1.1 focuses on stability and packaging rather than adding another
detector name to the interface.

## Changes

- Constrained, clipped and resizable preview canvas.
- Stable manual-frame identity, per-scan undo/redo and explicit reading-order
  renumbering.
- Geometry guards for moves, resizes and likely duplicate frames.
- Atomic current/all-scan re-detection with full restoration after cancellation
  or failure.
- One stable detector for all published film formats; no Classic UI or fallback.
- Leaner offline Apple Silicon runtime containing CPython, NumPy and tifffile.
- Product version `1.1`, bundle version `1.1` (`11000`) and planned tag
  `v1.1.0`.

## Publication gate

The locally generated ZIP is a release candidate, not yet a public signed
release. Before publishing `v1.1.0`, complete the real-scan format matrix, sign
with Warsawying’s Developer ID, notarize, staple, and repeat the offline macOS
14 installation/upgrade/rollback test.

Copyright © 2026 Warsawying.
