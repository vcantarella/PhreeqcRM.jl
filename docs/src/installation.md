# Installation

The package is not registered yet. Until the Yggdrasil-built `PhreeqcRM_jll`
exists you need to build `libphreeqcrm` locally.

## 1. Build libphreeqcrm

Requirements: CMake ≥ 3.13, a C++ compiler, and (on macOS) `libomp` from
Homebrew.

```bash
git clone https://github.com/vcantarella/PhreeqcRM.jl.git
cd PhreeqcRM.jl
bash deps/build_phreeqcrm.sh
```

This clones the upstream USGS source at a pinned tag (`v3.9.0`), builds a
shared library with OpenMP, and installs to `deps/usr/`.

The macOS build automatically picks up `libomp` from Homebrew if present.
Without `libomp`, the dylib falls back to single-threaded and OpenMP-related
tests are no-ops. Install with `brew install libomp`.

## 2. Point Julia at the library

```bash
export JULIA_PHREEQCRM_PATH="$PWD/deps/usr/lib/libPhreeqcRM.dylib"   # macOS
# Linux:   export JULIA_PHREEQCRM_PATH="$PWD/deps/usr/lib/libPhreeqcRM.so"
```

The local `PhreeqcRM_jll` stub reads this env var at module load. When the
Yggdrasil JLL ships, it'll be a one-line drop-in and the env var goes away.

## 3. Use the package

```bash
julia --project=PhreeqcRM
```

```julia
julia> using PhreeqcRM
julia> rm = PhreeqcRMInstance(10)
julia> close(rm)
```
