#!/usr/bin/env bash
# Rebuild the macOS wheels for aiohttp 3.0.8+sp1.
#
# Why this exists: 3.0.8's original macOS CI is dead, and the build needs old
# CPython on macOS — the only thing that runs on current macOS is conda-forge's
# x86_64 interpreters (python.org's old .pkg builds crash: CoreFoundation/dyld).
#
# Requirements: an INTEL macOS host (x86_64) — e.g. a physical Intel Mac, or the
# `macos-15-intel` GitHub runner (see process/macos-build.yml). Conda is auto-
# installed (Miniforge) if missing. Produces wheels into ../build_output/; then run
# post_build to rename (+sp1) into seal_artifacts/.
#
# Tiers (all conda; cp34 macOS is intentionally out of scope — Py3.4 won't run on
# current macOS): cp35 -> macosx_10_10/10_11/10_12 ; cp36 -> macosx_10_11/10_12.
set -euxo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # the process/ dir
VDIR="$(dirname "$HERE")"                               # 3.0.8+sp1/
OUT="${OUT:-$VDIR/build_output}"; mkdir -p "$OUT"
TAG=v3.0.8
CYTHON=0.27.3            # matches the public 3.0.8 wheels' Generator/Cython

# Patched source: use $SOURCE if it already has the CVE patch applied (e.g. the
# checked-out fork); otherwise clone clean upstream and apply our patch.
if [ -n "${SOURCE:-}" ]; then
  SRC="$SOURCE"
else
  SRC="$(mktemp -d)/aiohttp"
  git clone --depth 1 --branch "$TAG" https://github.com/aio-libs/aiohttp.git "$SRC"
  git -C "$SRC" apply "$VDIR/patches/CVE-2025-69223.patch"
fi

# Conda (Miniforge) — install if absent.
if ! command -v conda >/dev/null 2>&1; then
  curl -fsSL -o /tmp/mf.sh https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-MacOSX-x86_64.sh
  bash /tmp/mf.sh -b -p "$HOME/miniforge3"
  export PATH="$HOME/miniforge3/bin:$PATH"
fi
source "$(conda info --base)/etc/profile.d/conda.sh"
# retag with the conda base python (modern) + a current `wheel` (has `tags`);
# the build envs pin wheel 0.30.0 which can't retag.
RETAG_PY="$(conda info --base)/bin/python"
"$RETAG_PY" -m pip install -q -U wheel

# build <conda-env> <deployment-target>  -> one retagged wheel into $OUT
build() {
  local ENV="$1" TARGET="$2"
  conda activate "$ENV"
  export MACOSX_DEPLOYMENT_TARGET="$TARGET" ARCHFLAGS="-arch x86_64"
  # conda's py3.5 distutils ignores MACOSX_DEPLOYMENT_TARGET (bakes 10.9); force the
  # min-version flag so the linker stamps LC_VERSION_MIN = the tag we ship.
  export CFLAGS="-Wno-error=implicit-function-declaration -Wno-error=implicit-int -mmacosx-version-min=$TARGET"
  export LDFLAGS="-mmacosx-version-min=$TARGET"
  python -m pip install -q "cython==$CYTHON" 'wheel==0.30.0' 'setuptools<46'
  rm -rf /tmp/wh; ( cd "$SRC" && rm -rf build && python setup.py bdist_wheel -d /tmp/wh )
  conda deactivate
  local T="${TARGET//./_}"
  "$RETAG_PY" -m wheel tags --platform-tag "macosx_${T}_x86_64" --remove /tmp/wh/*.whl
  mv /tmp/wh/*.whl "$OUT/"
}

conda create -y -n py35 -c conda-forge python=3.5.5
for t in 10.10 10.11 10.12; do build py35 "$t"; done

conda create -y -n py36 -c conda-forge python=3.6.15
for t in 10.11 10.12; do build py36 "$t"; done

echo "=== built into $OUT ==="
ls -la "$OUT"/*macosx*.whl
