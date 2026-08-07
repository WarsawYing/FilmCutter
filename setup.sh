#!/bin/bash
# FilmCutter Setup — run once to prepare the project
set -e
cd "$(dirname "$0")"

echo "=== FilmCutter Setup ==="

# 1. Python venv
VENV_PYTHON="PythonEngine/venv/bin/python3"

if [ -x "$VENV_PYTHON" ]; then
    if "$VENV_PYTHON" -c "import numpy, PIL, scipy, tifffile" >/dev/null 2>&1; then
        echo "Python environment is healthy."
    else
        echo "Python environment is incomplete; rebuilding it..."
        rm -rf "PythonEngine/venv"
    fi
elif [ -e "PythonEngine/venv" ] || [ -L "$VENV_PYTHON" ]; then
    echo "Python environment is broken; rebuilding it..."
    rm -rf "PythonEngine/venv"
fi

if [ ! -x "$VENV_PYTHON" ]; then
    echo "Creating Python virtual environment..."
    /usr/bin/python3 -m venv PythonEngine/venv
    echo "Installing Python dependencies..."
    "$VENV_PYTHON" -m pip install -r PythonEngine/requirements.txt
fi

"$VENV_PYTHON" -c "import numpy, PIL, scipy, tifffile; print('Python dependencies verified.')"

# 2. Build Swift app
echo "Building FilmCutter app..."
cd FilmCutterApp
swift build

echo ""
echo "Setup complete!"
echo "Launch with: cd FilmCutterApp && swift run"
