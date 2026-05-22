# PhreeqcRM.jl

[![CI](https://github.com/vcantarella/PhreeqcRM.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/vcantarella/PhreeqcRM.jl/actions/workflows/CI.yml)

Julia interface to USGS's [PhreeqcRM](https://water.usgs.gov/water-resources/software/PHREEQC/) — the reactive-transport reaction module bundled with PHREEQC. PhreeqcRM is a C++ class with a flat C façade (`RM_*` functions) designed to be the geochemistry step inside a transport simulator: each timestep the transport code calls `SetConcentrations` → `RunCells` → `GetConcentrations`.

This wrapper has two layers:

- **Low level** (`PhreeqcRM.LibPhreeqcRM`) — Clang.jl-generated `@ccall`s, one-to-one with the C header. Regenerated from `gen/generator.jl` by maintainers.
- **High level** (the documented surface) — `PhreeqcRMInstance` with finalizer + explicit `close`, typed `PhreeqcRMError` exceptions, per-domain unit `@enum`s, shape-validated concentration matrices, threading helpers.

## Status

Early. Not yet registered in the General Registry. The local-build path works on macOS and Linux; a Yggdrasil-built `PhreeqcRM_jll` is not yet published, so a local stub package (`PhreeqcRM_jll/` in this repo) handles library resolution from an env var for now.

## Quick start

```bash
# 1. Clone
git clone https://github.com/vcantarella/PhreeqcRM.jl.git
cd PhreeqcRM.jl

# 2. Build libphreeqcrm locally (CMake + a C++ compiler; macOS also needs `brew install libomp`)
bash deps/build_phreeqcrm.sh

# 3. Point Julia at the dylib and instantiate
export JULIA_PHREEQCRM_PATH="$PWD/deps/usr/lib/libPhreeqcRM.dylib"   # Linux: libPhreeqcRM.so
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

```julia
using PhreeqcRM

rm = PhreeqcRMInstance(40; nthreads = 1)
load_database!(rm, "deps/usr/share/doc/PhreeqcRM/database/phreeqc.dat")
run_string!(rm, """
    SOLUTION 1
        pH 7.0
        Na 1.0
        Cl 1.0 charge
    END
""")
set_units!(rm; solution = SolutionUnits.MolPerL)
set_porosity!(rm,              fill(0.3, 40))
set_saturation!(rm,            fill(1.0, 40))
set_representative_volume!(rm, fill(1.0, 40))
set_temperature!(rm,           fill(25.0, 40))
set_pressure!(rm,              fill(1.0,  40))
find_components!(rm)
set_initial_conditions!(rm; solution = fill(1, 40))

c = zeros_concentrations(rm)           # Matrix(nxyz, ncomps) — rows are cells
get_concentrations!(rm, c)
set_time!(rm, 0.0); set_time_step!(rm, 60.0)
run_cells!(rm)
get_concentrations!(rm, c)
close(rm)
```

See `examples/advection_reaction.jl` for a complete 40-cell cation exchange column transport.

## Repository layout

```
.
├── src/                   PhreeqcRM.jl wrapper source
├── test/                  TestItems-based test suite
│   ├── reference_suite/   29 upstream PHREEQC examples + per-case Julia/C drivers
│   └── c_build/           Makefile that builds C drivers against libPhreeqcRM
├── docs/                  Documenter.jl docs
├── benchmark/             BenchmarkTools suite + C vs Julia comparisons
├── examples/              Standalone usage demos
├── gen/                   Clang.jl bindings generator (maintainer-only)
├── ext/                   Package extensions (DataFrames, …)
├── deps/                  Local libphreeqcrm build script (deps/usr/ gitignored)
├── PhreeqcRM_jll/         Local JLL stub — resolves libphreeqcrm via env var.
│                          Disappears when the Yggdrasil-built JLL ships.
└── .github/workflows/     CI: tests across 3 OS × 3 Julia versions,
                           per-PR C-vs-Julia benchmark, docs
```

## What's validated

- **29 upstream PHREEQC examples** (ex1 through ex22 with sub-variants) load and run through `PhreeqcRM.jl` without errors.
- **Per-row numerical comparison** of PhreeqcRM ↔ PHREEQC CLI for three canonical patterns:
  - `ex11` — 1D transport + cation exchange (100 shifts × 5 columns, ~1% agreement)
  - `ex2`  — batch parameter sweep over temperature (51 cells × 4 columns, ~0.05 SI agreement)
  - `ex9`  — kinetic Fe(II) oxidation (11 time steps × 5 columns, ~0.1% agreement)
- **C vs Julia step-time** across all 29 cases: median wrapper overhead **0.98** (Julia/C ratio), max 1.15. The Julia wrapper adds essentially zero overhead — `RunCells` chemistry dominates wall-clock, FFI marshalling is in the noise.
- **Zero-allocation hot loop**: `set_concentrations!` + `run_cells!` + `get_concentrations!` allocate 0 bytes per step after warmup (asserted in the `:perf` test tier).

## License

[MIT](LICENSE) for the Julia wrapper. USGS PhreeqcRM itself is public domain.
