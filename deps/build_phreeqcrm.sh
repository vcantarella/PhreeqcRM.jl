#!/usr/bin/env bash
# Build libphreeqcrm locally for use with PhreeqcRM.jl.
#
# Outputs:
#   deps/src/        upstream phreeqcrm source at the pinned tag
#   deps/build/      cmake build tree
#   deps/usr/lib/    libPhreeqcRM.dylib (with @loader_path rpath, relocatable)
#   deps/usr/include/RM_interface_C.h    (header used by the Clang.jl generator)
#
# After a successful build:
#   export JULIA_PHREEQCRM_PATH="$PWD/deps/usr/lib/libPhreeqcRM.dylib"
#
# Override the pinned tag with PHREEQCRM_TAG, e.g.:
#   PHREEQCRM_TAG=v3.9.0 bash deps/build_phreeqcrm.sh

set -euo pipefail

PHREEQCRM_TAG="${PHREEQCRM_TAG:-v3.9.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/src"
BUILD="$SCRIPT_DIR/build"
PREFIX="$SCRIPT_DIR/usr"

echo "==> phreeqcrm tag: $PHREEQCRM_TAG"

if [[ ! -d "$SRC/.git" ]]; then
    echo "==> Cloning usgs-coupled/phreeqcrm"
    rm -rf "$SRC"
    git clone --depth 1 --branch "$PHREEQCRM_TAG" \
        https://github.com/usgs-coupled/phreeqcrm "$SRC"
else
    echo "==> Source already present at $SRC; verifying tag"
    cur="$(git -C "$SRC" describe --tags --exact-match 2>/dev/null || echo unknown)"
    if [[ "$cur" != "$PHREEQCRM_TAG" ]]; then
        echo "    current tag: $cur, requested: $PHREEQCRM_TAG"
        echo "    delete deps/src/ to re-clone at the requested tag"
        exit 1
    fi
fi

echo "==> Configuring with CMake"

# macOS clang doesn't ship omp.h; FindOpenMP fails silently and the library
# ends up single-threaded. If libomp is available via Homebrew, point CMake at
# it explicitly. On Linux + GCC, OpenMP is built into the compiler and these
# flags are skipped.
OMP_FLAGS=()
if [[ "$(uname -s)" == "Darwin" ]] && command -v brew >/dev/null 2>&1 && brew --prefix libomp >/dev/null 2>&1; then
    LIBOMP_PREFIX="$(brew --prefix libomp)"
    if [[ -f "$LIBOMP_PREFIX/include/omp.h" && -f "$LIBOMP_PREFIX/lib/libomp.dylib" ]]; then
        echo "    using libomp from $LIBOMP_PREFIX"
        OMP_FLAGS=(
            -DOpenMP_C_FLAGS="-Xclang -fopenmp -I$LIBOMP_PREFIX/include"
            -DOpenMP_C_LIB_NAMES=omp
            -DOpenMP_CXX_FLAGS="-Xclang -fopenmp -I$LIBOMP_PREFIX/include"
            -DOpenMP_CXX_LIB_NAMES=omp
            -DOpenMP_omp_LIBRARY="$LIBOMP_PREFIX/lib/libomp.dylib"
        )
    fi
fi

cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DBUILD_SHARED_LIBS=ON \
    -DPHREEQCRM_BUILD_MPI=OFF \
    -DPHREEQCRM_DISABLE_OPENMP=OFF \
    -DPHREEQCRM_WITH_YAML_CPP=OFF \
    -DPHREEQCRM_USE_ZLIB=OFF \
    "${OMP_FLAGS[@]}" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_RPATH="@loader_path" \
    -DCMAKE_INSTALL_NAME_DIR="@rpath"

echo "==> Building (this takes a few minutes)"
cmake --build "$BUILD" --parallel

echo "==> Installing to $PREFIX"
cmake --install "$BUILD"

echo
echo "==> Verifying built library"
# Upstream CMake produces libPhreeqcRM.{dylib,so,dll} (mixed case, matching the CMake
# target name). Find whatever the OS produced.
case "$(uname -s)" in
    Darwin) DYLIB_GLOB="$PREFIX/lib/libPhreeqcRM*.dylib" ;;
    Linux)  DYLIB_GLOB="$PREFIX/lib/libPhreeqcRM*.so*" ;;
    *)      DYLIB_GLOB="$PREFIX/{bin,lib}/PhreeqcRM*.dll" ;;
esac
DYLIB="$(ls -1 $DYLIB_GLOB 2>/dev/null | head -1)"
if [[ -z "${DYLIB:-}" || ! -f "$DYLIB" ]]; then
    echo "ERROR: no PhreeqcRM library matching $DYLIB_GLOB after install" >&2
    exit 1
fi

if command -v otool >/dev/null 2>&1; then
    otool -L "$DYLIB"
fi

# Capture symbols once — avoids `grep -q` + pipefail giving us SIGPIPE-141 when
# grep exits early and nm gets killed mid-write.
syms="$(nm -gU "$DYLIB" 2>/dev/null || true)"
missing=0
for sym in RM_Create RM_Destroy RM_LoadDatabase RM_RunCells RM_GetConcentrations; do
    if ! grep -qE "T _?$sym$" <<<"$syms"; then
        echo "ERROR: expected symbol $sym not found in $(basename "$DYLIB")" >&2
        missing=1
    fi
done
[[ $missing -eq 0 ]] || exit 1

HEADER="$PREFIX/include/RM_interface_C.h"
if [[ ! -f "$HEADER" ]]; then
    echo "ERROR: $HEADER not installed" >&2
    exit 1
fi

echo
echo "==> Success."
echo "    dylib:  $DYLIB"
echo "    header: $HEADER"
echo
echo "Set this in your shell before using PhreeqcRM.jl:"
echo
echo "    export JULIA_PHREEQCRM_PATH=\"$DYLIB\""
echo
