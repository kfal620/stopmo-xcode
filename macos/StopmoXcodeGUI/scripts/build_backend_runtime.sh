#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${GUI_ROOT}/../.." && pwd)"

OUT_DIR="${OUT_DIR:-${GUI_ROOT}/dist/backend-runtime}"
ARCHES="${ARCHES:-arm64 x86_64}"
RUNTIME_PYTHON="${RUNTIME_PYTHON:-/usr/bin/python3}"
EXTRAS="${EXTRAS:-watch,raw,ocio,io,video}"
PIP_CONSTRAINTS="${PIP_CONSTRAINTS:-}"

if [[ ! -x "$RUNTIME_PYTHON" ]]; then
  echo "python executable not found: $RUNTIME_PYTHON" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

build_arch_runtime() {
  local arch="$1"
  local arch_root="$OUT_DIR/$arch"
  local venv_dir="$arch_root/venv"

  echo "[backend-runtime] building architecture: $arch"
  rm -rf "$arch_root"
  mkdir -p "$arch_root"

  local -a create_cmd
  if [[ "$(uname -m)" == "$arch" ]]; then
    create_cmd=("$RUNTIME_PYTHON" -m venv "$venv_dir")
  else
    create_cmd=(arch "-$arch" "$RUNTIME_PYTHON" -m venv "$venv_dir")
  fi
  "${create_cmd[@]}"

  "$venv_dir/bin/python" -m pip install --upgrade pip setuptools wheel

  local -a pip_install=("$venv_dir/bin/python" -m pip install)
  if [[ -n "$PIP_CONSTRAINTS" ]]; then
    pip_install+=(--constraint "$PIP_CONSTRAINTS")
  fi
  pip_install+=("${REPO_ROOT}[${EXTRAS}]")
  "${pip_install[@]}"

  mkdir -p "$arch_root/bin"

  local imageio_ffmpeg_path
  imageio_ffmpeg_path="$($venv_dir/bin/python - <<'PY'
try:
    import imageio_ffmpeg  # type: ignore
    print(imageio_ffmpeg.get_ffmpeg_exe())
except Exception:
    print("")
PY
)"
  if [[ -n "$imageio_ffmpeg_path" && -x "$imageio_ffmpeg_path" ]]; then
    cp "$imageio_ffmpeg_path" "$arch_root/bin/ffmpeg"
    chmod +x "$arch_root/bin/ffmpeg"
  fi

  if command -v exiftool >/dev/null 2>&1; then
    cp "$(command -v exiftool)" "$arch_root/bin/exiftool" || true
  fi

  "$venv_dir/bin/python" -m pip freeze > "$arch_root/requirements.freeze.txt"
  "$venv_dir/bin/python" - <<'PY' "$arch_root/runtime-metadata.json" "$arch"
import json
import platform
import sys
from pathlib import Path

out_path = Path(sys.argv[1])
arch = sys.argv[2]
payload = {
    "arch": arch,
    "python_executable": sys.executable,
    "python_version": sys.version,
    "platform": platform.platform(),
}
out_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

for arch in $ARCHES; do
  build_arch_runtime "$arch"
done

"$RUNTIME_PYTHON" - <<'PY' "$OUT_DIR" $ARCHES
import hashlib
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1]).resolve()
arches = sys.argv[2:]
manifest = {
    "output_root": str(out_dir),
    "architectures": [],
}

for arch in arches:
    arch_root = out_dir / arch
    if not arch_root.exists():
        continue
    freeze_file = arch_root / "requirements.freeze.txt"
    freeze_sha = None
    if freeze_file.exists():
        freeze_sha = hashlib.sha256(freeze_file.read_bytes()).hexdigest()
    ffmpeg_path = arch_root / "bin" / "ffmpeg"
    manifest["architectures"].append(
        {
            "arch": arch,
            "runtime_root": str(arch_root),
            "venv_python": str(arch_root / "venv" / "bin" / "python"),
            "requirements_file": str(freeze_file) if freeze_file.exists() else None,
            "requirements_sha256": freeze_sha,
            "ffmpeg_bundled": ffmpeg_path.exists(),
            "ffmpeg_path": str(ffmpeg_path) if ffmpeg_path.exists() else None,
            "metadata_file": str(arch_root / "runtime-metadata.json"),
        }
    )

manifest_path = out_dir / "manifest.json"
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(f"wrote {manifest_path}")
PY

echo "[backend-runtime] complete: $OUT_DIR"
