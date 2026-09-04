#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
source "$ROOT/VERSION"
ZIP="${1:-$ROOT/dist/$release_asset}"
VERIFY=$(mktemp -d /tmp/filmcutter-verify.XXXXXX)
trap 'rm -rf "$VERIFY"' EXIT
ditto -x -k "$ZIP" "$VERIFY"
if unzip -l "$ZIP" | rg -q '__MACOSX|/\._'; then
  echo "Release contains AppleDouble metadata" >&2
  exit 1
fi
PACKAGE="$VERIFY"
[[ -d "$VERIFY/package" ]] && PACKAGE="$VERIFY/package"
APP="$PACKAGE/FilmCutter.app"
while IFS= read -r line; do
  expected="${line%% *}"
  relative="${line#*  }"
  [[ "$(cd "$PACKAGE" && shasum -a 256 "$relative" | awk '{print $1}')" == "$expected" ]]
done < "$PACKAGE/CHECKSUMS.txt"
[[ -x "$APP/Contents/MacOS/FilmCutter" ]]
[[ "$(file "$APP/Contents/MacOS/FilmCutter")" == *arm64* ]]
for locale in en zh-Hans ja es fr; do
  [[ -f "$APP/Contents/Resources/$locale.lproj/Localizable.strings" ]]
done
[[ -f "$APP/Contents/Resources/FilmCutter.icns" ]]
codesign --verify --deep --strict "$APP"
PY="$APP/Contents/Resources/PythonRuntime/bin/python3"
"$PY" -B -I -c 'import numpy,tifffile; print(numpy.__version__, tifffile.__version__)'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$bundle_short_version" ]]
if "$PY" -B -I -c 'import pip' >/dev/null 2>&1; then
  echo "Release runtime unexpectedly contains pip" >&2
  exit 1
fi
for module in scipy PIL cv2; do
  if "$PY" -B -I -c "import $module" >/dev/null 2>&1; then
    echo "Release runtime unexpectedly contains $module" >&2
    exit 1
  fi
done
[[ ! -d "$APP/Contents/Resources/PythonRuntime/lib/python3.13/site-packages/numpy/tests" ]]
[[ ! -d "$APP/Contents/Resources/PythonRuntime/lib/python3.13/site-packages/numpy/f2py" ]]
echo '{"command":"ping"}' | "$PY" -B -I "$APP/Contents/Resources/PythonEngine/engine.py" | grep -q '"status": "ok"'
if find "$APP/Contents/Resources/PythonEngine" -type f | rg -qi 'classic|legacy'; then
  echo "Release unexpectedly contains an old detector path" >&2
  exit 1
fi
if rg -a -q '/Users/|/private/tmp|/tmp/|/opt/homebrew|PythonEngine/venv' "$APP/Contents/MacOS" "$APP/Contents/Resources/PythonEngine"; then
  echo "Release contains a development-machine path" >&2
  exit 1
fi
if otool -L "$APP/Contents/MacOS/FilmCutter" | rg -q '/Users/|/opt/homebrew'; then
  echo "Release links a development-machine library" >&2
  exit 1
fi
[[ "$(stat -f %z "$ZIP")" -le 73400320 ]]
echo "Release verification passed: $ZIP"
