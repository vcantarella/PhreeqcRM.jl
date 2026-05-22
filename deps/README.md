# Local libphreeqcrm build

This directory builds a relocatable `libphreeqcrm.dylib` from upstream USGS
[`usgs-coupled/phreeqcrm`](https://github.com/usgs-coupled/phreeqcrm) for use
with the local `PhreeqcRM_jll` stub package, which `PhreeqcRM.jl` depends on.

The artifacts here are entirely local — none of `src/`, `build/`, or `usr/`
are tracked in git.

## Prerequisites

- CMake ≥ 3.13
- A C++ compiler (Apple clang, GCC, or MSVC)
- Git

## Build

```bash
bash deps/build_phreeqcrm.sh
```

This will:

1. Clone `usgs-coupled/phreeqcrm` at the pinned tag (`v3.9.0`) into `deps/src/`.
2. Configure with CMake (shared library, RelWithDebInfo, no MPI, OpenMP on,
   `@loader_path` rpath so the dylib is relocatable inside this tree).
3. Build in parallel.
4. Install to `deps/usr/{lib,include}`.
5. Verify a few core `RM_*` symbols are exported and the C header is installed.

Pin a different upstream tag with `PHREEQCRM_TAG=v3.8.8 bash deps/build_phreeqcrm.sh`.

## Point Julia at it

After the build, export the path to the dylib before starting Julia:

```bash
export JULIA_PHREEQCRM_PATH="$PWD/deps/usr/lib/libPhreeqcRM.dylib"
julia --project=.
```

(Linux: `libPhreeqcRM.so`. Windows: `PhreeqcRM.dll`. Upstream CMake names the
output after the CMake target, which is `PhreeqcRM` — mixed case.)

`PhreeqcRM_jll/src/PhreeqcRM_jll.jl` reads this env var to locate the library.
When the official `PhreeqcRM_jll` ships via Yggdrasil, this env-var dance goes
away and the JLL provides the path automatically.

## Cleanup

```bash
rm -rf deps/src deps/build deps/usr
```
