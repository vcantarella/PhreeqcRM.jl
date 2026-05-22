# PhreeqcRM.jl

Julia interface to USGS's [PhreeqcRM](https://water.usgs.gov/water-resources/software/PHREEQC/),
the reactive-transport reaction module bundled with PHREEQC. PhreeqcRM is a C++
class with a flat C façade (`RM_*` functions) designed to be the geochemistry
step inside a transport simulator: each timestep the transport code calls
`SetConcentrations` → `RunCells` → `GetConcentrations`.

This package wraps the C interface in two layers:

- **Low level** (`PhreeqcRM.LibPhreeqcRM`): Clang.jl-generated `@ccall`s, one-to-one
  with the C header. Regenerated from `gen/generator.jl` by maintainers.
- **High level** (the documented surface): `PhreeqcRMInstance` with a finalizer
  + explicit `close`, typed `PhreeqcRMError` exceptions, per-domain unit
  `@enum`s, shape-validated concentration matrices, threading helpers.

## Quickstart

```julia
using PhreeqcRM

rm = PhreeqcRMInstance(40; nthreads = 1)
load_database!(rm, "/path/to/phreeqc.dat")
run_string!(rm, \"\"\"
    SOLUTION 1
        pH 7.0
        Na 1.0
        Cl 1.0 charge
    END
\"\"\")
set_units!(rm; solution = SolutionUnits.MolPerL)
set_porosity!(rm,              fill(0.3, 40))
set_saturation!(rm,            fill(1.0, 40))
set_representative_volume!(rm, fill(1.0, 40))
set_temperature!(rm,           fill(25.0, 40))
set_pressure!(rm,              fill(1.0,  40))
find_components!(rm)
set_initial_conditions!(rm; solution = fill(1, 40))

c = zeros_concentrations(rm)               # Matrix(nxyz, ncomps)
get_concentrations!(rm, c)
set_time!(rm, 0.0); set_time_step!(rm, 60.0)
run_cells!(rm)
get_concentrations!(rm, c)
close(rm)
```

See [`examples/advection_reaction.jl`](https://github.com/vcantarella/PhreeqcRM.jl/blob/main/examples/advection_reaction.jl)
for a complete end-to-end column transport with cation exchange.

## Status

Early. The local-build path (`deps/build_phreeqcrm.sh`) works on macOS and Linux;
a Yggdrasil-built `PhreeqcRM_jll` is not yet published. Once the JLL ships, the
local stub goes away with no source changes in this package.
