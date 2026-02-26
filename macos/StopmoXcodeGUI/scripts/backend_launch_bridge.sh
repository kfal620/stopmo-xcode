#!/usr/bin/env bash
set -euo pipefail

BACKEND_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

arch_name="$(uname -m)"
case "$arch_name" in
  arm64|x86_64)
    runtime_arch="$arch_name"
    ;;
  *)
    echo "unsupported runtime architecture: $arch_name" >&2
    exit 1
    ;;
esac

RUNTIME_DIR="$BACKEND_ROOT/runtimes/$runtime_arch"
PYTHON_BIN="$RUNTIME_DIR/venv/bin/python3"
if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="$RUNTIME_DIR/venv/bin/python"
fi
if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "bundled Python runtime missing for architecture: $runtime_arch" >&2
  exit 1
fi

export STOPMO_XCODE_RUNTIME_MODE="bundled"
export STOPMO_XCODE_BACKEND_ROOT="$RUNTIME_DIR"

if [[ -n "${STOPMO_XCODE_WORKSPACE_ROOT:-}" ]]; then
  cd "$STOPMO_XCODE_WORKSPACE_ROOT"
fi

if [[ -x "$RUNTIME_DIR/bin/ffmpeg" ]]; then
  export STOPMO_XCODE_FFMPEG="$RUNTIME_DIR/bin/ffmpeg"
fi

if [[ -d "$RUNTIME_DIR/bin" ]]; then
  export PATH="$RUNTIME_DIR/bin:$PATH"
fi

exec "$PYTHON_BIN" -m stopmo_xcode.gui_bridge "$@"
