#!/bin/zsh
# Developer bootstrap only. End users use 安装 FilmCutter.command from Releases.
set -euo pipefail
cd "${0:A:h}"
[[ -f vendor/runtime/cpython-3.13.15+20260807-aarch64-apple-darwin-install_only_stripped.tar.gz ]] || {
  echo "Pinned offline runtime is missing. Run scripts/prepare_vendor.sh once while online." >&2
  exit 1
}
scripts/build_release.sh
RUNTIME_PY="$PWD/.release-work/FilmCutter.app/Contents/Resources/PythonRuntime/bin/python3"
"$RUNTIME_PY" -B PythonEngine/test_engine.py
CLANG_MODULE_CACHE_PATH=/tmp/filmcutter-clang-cache \
SWIFT_MODULE_CACHE_PATH=/tmp/filmcutter-swift-cache \
swift test --package-path FilmCutterApp --disable-sandbox
echo "Developer environment ready. Run: FILMCUTTER_DEV_PYTHON=$RUNTIME_PY swift run --package-path FilmCutterApp"
