# FilmCutter 1.1

FilmCutter 1.1 is the next Apple Silicon release by Warsawying.

This release adds a five-language interface, reversible import/adjust/export
workflow, smart Unicode naming, one stable detection pipeline for the published format
list, and optional experimental boundary refinement with automatic fallback.
The download is self-contained and runs offline on macOS 14 or later.

Current limitations:

- Input is limited to uncompressed, single-page 8/16-bit grayscale or RGB TIFF.
- Real-scan validation currently covers the available 135 positive and negative
  fixtures. Other published formats remain provisional until the documented sample and
  IoU gates are complete.
- This local release candidate is ad-hoc signed. The first launch may require right-clicking the app
  and choosing Open, or approving it in Privacy & Security.
- Public 1.1 release requires Developer ID signing, notarization, stapling, and the full
  real-scan matrix described in `test-fixtures/manifest.json`.

Copyright © 2026 Warsawying. Source code is licensed under AGPL-3.0.
