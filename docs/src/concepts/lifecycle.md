# Lifecycle & call order

PhreeqcRM is stateful: some calls **must** come before others or they silently
do the wrong thing.

## The mandatory order

```text
PhreeqcRMInstance(nxyz; ...)         (1)  Create + SetComponentH2O
  ↓
load_database!(rm, "phreeqc.dat")    (2)  database elements + log K
  ↓
run_file!(rm, "input.pqi")           (3)  parse SOLUTION / EXCHANGE / RATES etc.
  ↓
find_components!(rm)                 (4)  discover components → fixes ncomps
  ↓
set_mapping!(rm, ...)                (5)  optional; default identity
set_units!(rm; solution = ..., ...)        (6)  solution unit is required
set_porosity!(rm, ...) etc.          (7)  per-cell physics
  ↓
set_initial_conditions!(rm; ...)     (8)  assign numbered reactant blocks
  ↓
set_time!(rm, t)                     (9a) before run_cells! or kinetics step 0
set_time_step!(rm, dt)               (9b) before run_cells!
  ↓
run_cells!(rm)                       (10) per-cell reaction step
get_concentrations!(rm, c)           (11) pull results
  ↓
close(rm)                            (12) preferred teardown
```

## Why each rule matters

| Rule | Failure mode if violated |
|---|---|
| `component_h2o` on constructor (before `load_database!`) | Database parses elements without separating water, ncomps will be wrong |
| `load_database!` before `run_file!` | Script references elements that aren't defined yet |
| `run_file!` before `find_components!` | InitialPhreeqc is empty, ncomps = 0 |
| `find_components!` before `zeros_concentrations` / `set_concentrations!` | Concentration buffer would be sized 0 × nxyz |
| `set_units!(...; solution=...)` before `set_concentrations!` | Numeric values silently misinterpreted (mol/L treated as mg/L, etc.) |
| `set_time!` + `set_time_step!` before `run_cells!` | Kinetics integrate over zero time, no kinetic effect |
| `close(rm)` before drop | OK — finalizer is a safety net, but join-on-OMP-threads at GC time is risky |

## Teardown

`close(rm)` is the documented teardown. It's idempotent — repeated calls are
no-ops after the first. The finalizer calls `close(rm)` as a safety net if
the handle is dropped without closing, but **don't rely on it**:
`RM_Destroy` joins on internal OpenMP threads, which is not something you
want firing from arbitrary GC contexts.

[`PhreeqcRM.with_instance`](@ref) is the preferred RAII-style pattern:

```julia
PhreeqcRM.with_instance(40; nthreads = 4) do rm
    load_database!(rm, "phreeqc.dat")
    # ... work ...
end   # close() called even if the block throws
```
