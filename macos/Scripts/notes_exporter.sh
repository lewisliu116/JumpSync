#!/bin/bash
# Note Exporter Bridge using apple-notes-parser

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_DIR="$SCRIPT_DIR/export_json"
MEDIA_DIR="$SCRIPT_DIR/export_media"
UV_DIR="$SCRIPT_DIR/uv_bin"

mkdir -p "$EXPORT_DIR"
mkdir -p "$MEDIA_DIR"
mkdir -p "$UV_DIR"

export UV_INSTALL_DIR="$UV_DIR"
export UV_CACHE_DIR="$SCRIPT_DIR/uv_cache"
export UV_TOOL_DIR="$SCRIPT_DIR/uv_tools"
export UV_PYTHON_INSTALL_DIR="$SCRIPT_DIR/uv_python"

mkdir -p "$UV_CACHE_DIR"
mkdir -p "$UV_PYTHON_INSTALL_DIR"

if ! command -v uv &> /dev/null; then
    if [ ! -f "$UV_DIR/uv" ]; then
        echo "Installing uv locally..." >&2
        curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1
    fi
    export PATH="$UV_DIR:$PATH"
fi

if [ -f "$EXPORT_DIR/notes.json" ]; then
    rm "$EXPORT_DIR/notes.json"
fi

# Create a local virtual environment so we can patch the third-party Apple Notes Parser bug
VENV_DIR="$SCRIPT_DIR/venv"
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment and installing apple-notes-parser..." >&2
    uv venv --python 3.11 "$VENV_DIR" >/dev/null 2>&1
    VIRTUAL_ENV="$VENV_DIR" uv pip install --python "$VENV_DIR" apple-notes-parser >/dev/null 2>&1

    # Patch the pathlib rglob bug related to "**" syntax
    TARGET_FILE=$(find "$VENV_DIR" -name "models.py" | grep "apple_notes_parser" | head -n 1)
    if [ -f "$TARGET_FILE" ]; then
        sed -i '' 's/media_base.rglob(filename_basename)/media_base.rglob(filename_basename.replace("**", "*"))/g' "$TARGET_FILE" 2>/dev/null || \
        sed -i 's/media_base.rglob(filename_basename)/media_base.rglob(filename_basename.replace("**", "*"))/g' "$TARGET_FILE"
    fi
fi

echo "Extracting notes to JSON..." >&2
"$VENV_DIR/bin/apple-notes-parser" export "$EXPORT_DIR/notes.json" >&2

echo "Extracting media attachments..." >&2
"$VENV_DIR/bin/apple-notes-parser" attachments --save "$MEDIA_DIR" >&2

cat <<EOF
{
  "exportFile": "$EXPORT_DIR/notes.json",
  "mediaDir": "$MEDIA_DIR"
}
EOF
