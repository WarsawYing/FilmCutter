# DNG roadmap

FilmCutter 1.1 remains TIFF-only. DNG support should be developed as a separate
input-decoding layer after the 1.1 stability release, not by adding a large RAW
Python stack to the current detector.

## Recommended first milestone: 1.2 Beta

- Accept a DNG as input and export independent 16-bit TIFF frames.
- Decode through Apple Core Image `CIRAWFilter` on macOS 14+, using the native
  image size, embedded orientation and a fixed, documented set of RAW controls.
- Feed a bounded RGB preview into the existing detector, then map every detected
  rectangle back into oriented full-resolution coordinates.
- Render only approved crops where the Apple API permits it; otherwise render
  one full-resolution intermediate into a private temporary directory and
  remove it after a successful or failed job.
- Reject unsupported files before detection with a stable error code. Never
  silently fall back to an embedded low-resolution JPEG preview for export.

Apple API reference: <https://developer.apple.com/documentation/coreimage/cirawfilter>

## Decoder boundary

The Swift side should own the format-specific decoding behind a small interface:

```swift
protocol RasterInputDecoder {
    func inspect(_ source: URL) async throws -> RasterAssetInfo
    func makeDetectionProxy(_ source: URL, maximumSide: Int) async throws -> DetectionProxy
    func renderCrop(_ source: URL, rect: CGRect, destination: URL) async throws
}
```

`DetectionProxy` must record source dimensions, decoded dimensions, orientation,
active image area and both coordinate transforms. The detector continues to
receive ordinary raster pixels and therefore does not need to understand RAW
metadata.

## Why DNG-to-DNG cropping is not the first target

A DNG may contain mosaic CFA data or linear RAW data, active-area/default-crop
tags, black-level tables, color matrices, opcode lists, masked pixels, previews
and private camera metadata. Cropping the raw mosaic also changes the CFA phase
when the origin moves. Rewriting all of those relationships safely is a format
writer project, not a simple rectangle crop.

The authoritative format reference is Adobe’s
[Digital Negative Specification 1.7.1](https://helpx.adobe.com/content/dam/help/en/photoshop/pdf/DNG_Spec_1_7_1_0.pdf).

If photographers need to preserve the original RAW before DNG writing is ready,
FilmCutter should save a small non-destructive JSON recipe containing source
hash, orientation, crop rectangles and render settings. A later version can
evaluate linear-DNG output without promising mosaic-DNG preservation.

## Fallback and dependency policy

Test Apple decoding first on the published fixture matrix. Only consider LibRaw
if real cameras reveal an unacceptable compatibility gap. LibRaw supports DNG,
but bundling it adds native-library maintenance and LGPL/CDDL compliance work:
<https://www.libraw.org/docs>.

Do not add rawpy, OpenCV, SciPy, Pillow, a machine-learning model or a background
download merely to enable DNG input.

## DNG test gate

- At least two materially different DNGs from every advertised camera/scanner
  family, including rotated files and both CFA and LinearRaw examples.
- Detection proxy/full-resolution coordinate round trips within one pixel.
- Fixed render settings produce deterministic dimensions, bit depth and color
  profile on supported macOS versions.
- Embedded-preview-only, corrupt, unsupported and unusually large DNGs fail
  without losing the current FilmCutter session.
- TIFF behavior, package size and offline operation remain unchanged.
