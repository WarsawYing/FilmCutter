#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
source "$ROOT/runtime.lock"
mkdir -p "$ROOT/vendor/runtime" "$ROOT/vendor/wheels"
ARCHIVE="$ROOT/vendor/runtime/$asset"
if [[ ! -f "$ARCHIVE" ]] || [[ "$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')" != "$sha256" ]]; then
  curl -fL "$url" -o "$ARCHIVE.partial"
  [[ "$(shasum -a 256 "$ARCHIVE.partial" | awk '{print $1}')" == "$sha256" ]] || { echo "Runtime hash mismatch" >&2; exit 1; }
  mv "$ARCHIVE.partial" "$ARCHIVE"
fi
python3 -m pip download --only-binary=:all: --platform macosx_14_0_arm64 \
  --python-version 3.13 --implementation cp --abi cp313 \
  --dest "$ROOT/vendor/wheels" numpy==2.5.1 tifffile==2026.7.14
python3 -m pip hash "$ROOT"/vendor/wheels/*.whl
echo "Verify these hashes still match requirements-runtime.lock before publishing."
