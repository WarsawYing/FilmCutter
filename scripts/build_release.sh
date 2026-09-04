#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
source "$ROOT/runtime.lock"
source "$ROOT/VERSION"
ZIP_NAME="$release_asset"
ARCHIVE="$ROOT/vendor/runtime/$asset"
[[ -f "$ARCHIVE" ]] || { echo "Missing vendor runtime. Run scripts/prepare_vendor.sh" >&2; exit 1; }
[[ "$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')" == "$sha256" ]] || { echo "Runtime hash mismatch" >&2; exit 1; }
WHEELS=("$ROOT"/vendor/wheels/*.whl)
(( ${#WHEELS} == 2 )) || { echo "Expected exactly NumPy and tifffile wheels" >&2; exit 1; }
grep -q '6165343f81b56ef8f514f396989e529b61d9dc709b99421b07e9f3e698e2287d' "$ROOT/requirements-runtime.lock"
grep -q '4eb20372e76edf2c9fed922b1e3a0a0567be3560bd2008336115763bb1f3c034' "$ROOT/requirements-runtime.lock"

WORK="$ROOT/.release-work"
DIST="$ROOT/dist"
APP="$WORK/FilmCutter.app"
rm -rf "$WORK" "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/PythonEngine" "$APP/Contents/Resources/PythonRuntime" "$DIST/package"
mkdir -p "$APP/Contents/Resources/PythonEngine/detectors/v2"

SWIFT_RELEASE_BUILD="$ROOT/.swift-release-build"
CLANG_MODULE_CACHE_PATH="$SWIFT_RELEASE_BUILD/clang-cache" \
SWIFT_MODULE_CACHE_PATH="$SWIFT_RELEASE_BUILD/swift-cache" \
swift build --package-path "$ROOT/FilmCutterApp" -c release --disable-sandbox --scratch-path "$SWIFT_RELEASE_BUILD" \
  -Xswiftc -file-prefix-map -Xswiftc "$ROOT=." \
  -Xswiftc -debug-prefix-map -Xswiftc "$ROOT=."
cp "$SWIFT_RELEASE_BUILD/arm64-apple-macosx/release/FilmCutterApp" "$APP/Contents/MacOS/FilmCutter"
strip -S "$APP/Contents/MacOS/FilmCutter"
cp "$ROOT/PythonEngine/engine.py" "$ROOT/PythonEngine/image_reader.py" \
  "$ROOT/PythonEngine/processor.py" "$ROOT/PythonEngine/debug_log.py" \
  "$APP/Contents/Resources/PythonEngine/"
cp "$ROOT/PythonEngine/detectors/__init__.py" "$APP/Contents/Resources/PythonEngine/detectors/"
cp "$ROOT/PythonEngine/detectors/v2/__init__.py" \
  "$ROOT/PythonEngine/detectors/v2/detector.py" \
  "$ROOT/PythonEngine/detectors/v2/thumbnail.py" \
  "$APP/Contents/Resources/PythonEngine/detectors/v2/"
cp "$ROOT/FilmCutterApp/Sources/Resources/logo.svg" "$APP/Contents/Resources/logo.svg"
cp "$ROOT/FilmCutterApp/Sources/Resources/FilmCutter.icns" "$APP/Contents/Resources/FilmCutter.icns"
xcstrings_out="$WORK/xcstrings"
xcrun xcstringstool compile "$ROOT/FilmCutterApp/Sources/Resources/Localizable.xcstrings" \
  --output-directory "$xcstrings_out"
cp -R "$xcstrings_out/" "$APP/Contents/Resources/"

tar -xzf "$ARCHIVE" -C "$APP/Contents/Resources/PythonRuntime" --strip-components=1
RUNTIME_PY="$APP/Contents/Resources/PythonRuntime/bin/python3"
"$RUNTIME_PY" -m pip install --no-index --no-deps --target "$APP/Contents/Resources/PythonRuntime/lib/python3.13/site-packages" "${WHEELS[@]}"
runtime_site="$APP/Contents/Resources/PythonRuntime/lib/python3.13/site-packages"
rm -rf "$runtime_site/pip" "$runtime_site/setuptools" "$runtime_site/wheel" "$runtime_site/bin"
find "$runtime_site" -maxdepth 1 -type d \
  \( -name 'pip-*.dist-info' -o -name 'setuptools-*.dist-info' -o -name 'wheel-*.dist-info' \) \
  -exec rm -rf {} +
find "$runtime_site" -type d \( -name tests -o -name test \) -prune -exec rm -rf {} +
rm -rf "$runtime_site/numpy/f2py" "$runtime_site/numpy/typing/tests"
rm -rf "$APP/Contents/Resources/PythonRuntime/include" "$APP/Contents/Resources/PythonRuntime/share" \
  "$APP/Contents/Resources/PythonRuntime/lib/pkgconfig" "$APP/Contents/Resources/PythonRuntime/lib/python3.13/test" \
  "$APP/Contents/Resources/PythonRuntime/lib/python3.13/idlelib" "$APP/Contents/Resources/PythonRuntime/lib/python3.13/tkinter" \
  "$APP/Contents/Resources/PythonRuntime/lib/python3.13/ensurepip" "$APP/Contents/Resources/PythonRuntime/lib/python3.13/venv" \
  "$APP/Contents/Resources/PythonRuntime/lib/python3.13/turtledemo" "$APP/Contents/Resources/PythonRuntime/lib/python3.13/__phello__"
rm -rf "$APP/Contents/Resources/PythonRuntime/lib/python3.13/pydoc_data"
rm -f "$APP/Contents/Resources/PythonRuntime/bin/idle"* \
  "$APP/Contents/Resources/PythonRuntime/bin/pip"* \
  "$APP/Contents/Resources/PythonRuntime/bin/pydoc"* \
  "$APP/Contents/Resources/PythonRuntime/bin/python3-config" \
  "$APP/Contents/Resources/PythonRuntime/bin/python3.13-config"
rm -rf "$APP/Contents/Resources/PythonRuntime/lib/tcl9.0" \
  "$APP/Contents/Resources/PythonRuntime/lib/tcl9" \
  "$APP/Contents/Resources/PythonRuntime/lib/tk9.0" \
  "$APP/Contents/Resources/PythonRuntime/lib/thread3.0.6" \
  "$APP/Contents/Resources/PythonRuntime/lib/itcl4.3.8"
rm -f "$APP/Contents/Resources/PythonRuntime/lib/libtcl"*.dylib
rm -f "$APP/Contents/Resources/PythonRuntime/lib/python3.13/lib-dynload/_tkinter"*.so
find "$APP" -name '__pycache__' -type d -prune -exec rm -rf {} +

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>FilmCutter</string>
<key>CFBundleIdentifier</key><string>com.warsawying.FilmCutter</string>
<key>CFBundleName</key><string>FilmCutter</string>
<key>CFBundleDisplayName</key><string>FilmCutter</string>
<key>CFBundleIconFile</key><string>FilmCutter.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${bundle_short_version}</string>
<key>CFBundleVersion</key><string>${bundle_build}</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSArchitecturePriority</key><array><string>arm64</string></array>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string><string>ja</string><string>es</string><string>fr</string></array>
</dict></plist>
PLIST

cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
find "$APP/Contents/Resources/PythonRuntime" -type f \( -name '*.so' -o -name '*.dylib' -o -perm +111 \) -exec codesign --force --sign - {} \;
codesign --force --deep --sign - "$APP"
COPYFILE_DISABLE=1 cp -R "$APP" "$DIST/package/"
cp "$ROOT/release/安装 FilmCutter.command" "$ROOT/release/README.txt" \
  "$ROOT/release/RELEASE_NOTES.md" "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$DIST/package/"
chmod +x "$DIST/package/安装 FilmCutter.command"
(cd "$DIST/package" && find . \( -type f -o -type l \) ! -name CHECKSUMS.txt -print0 | sort -z | xargs -0 shasum -a 256) > "$DIST/package/CHECKSUMS.txt"
(cd "$DIST" && COPYFILE_DISABLE=1 zip -qry --symlinks "$DIST/$ZIP_NAME" package)
ZIP_SIZE=$(stat -f %z "$DIST/$ZIP_NAME")
(( ZIP_SIZE <= 73400320 )) || { echo "ZIP exceeds 70 MiB: $ZIP_SIZE" >&2; exit 1; }
(cd "$DIST" && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")
"$ROOT/scripts/verify_release.sh" "$DIST/$ZIP_NAME"
