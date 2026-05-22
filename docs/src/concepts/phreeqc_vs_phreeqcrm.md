# PHREEQC vs PhreeqcRM — where chemistry lives

A common source of confusion: PhreeqcRM does **not** replace PHREEQC's input
language. The chemistry — what minerals can precipitate, what exchange sites
exist, what kinetic rate laws govern dissolution — is **still defined in a
PHREEQC input script** using the same keyword blocks the standalone `phreeqc`
CLI consumes. PhreeqcRM's job is to consume that script once and drive the
per-cell chemistry calculations from a transport simulator.

PhreeqcRM.jl does **not** expose `SOLUTION` / `EXCHANGE` / `EQUILIBRIUM_PHASES`
etc. as Julia structs. Doing so would mean reimplementing PHREEQC's parser,
which is large, evolving, and out of scope. You hand PhreeqcRM a `.pqi` file
(or a string), and the Julia side controls *which* numbered solution / exchange
/ etc. lives in *which* cell.

## Where each concept is defined

| Concept | Defined in | Referenced from Julia |
|---|---|---|
| Elements, species, log K, Debye–Hückel | **Database file** (`phreeqc.dat`, `llnl.dat`, …) | [`load_database!`](@ref) |
| Numbered `SOLUTION` (initial & boundary) | Script | [`run_file!`](@ref), then [`set_initial_conditions!`](@ref) |
| `EQUILIBRIUM_PHASES`, `EXCHANGE`, `SURFACE` | Script | [`set_initial_conditions!`](@ref) with `equilibrium_phases=…`, etc. |
| `GAS_PHASE`, `SOLID_SOLUTIONS` | Script | [`set_initial_conditions!`](@ref) |
| `KINETICS` + `RATES` (Basic rate-law code) | Script | [`set_initial_conditions!`](@ref) with `kinetics=…` |
| Which columns to retrieve | Script: `SELECTED_OUTPUT 1 …` | [`enable_selected_output!`](@ref) + [`get_selected_output`](@ref) |
| Number of cells (`nxyz`) | Julia | [`PhreeqcRMInstance`](@ref) constructor |
| Cell mapping | Julia | [`set_mapping!`](@ref) |
| Porosity, saturation, T, P, density | Julia (per timestep if you want) | [`set_porosity!`](@ref), [`set_saturation!`](@ref), etc. |
| Component concentrations per cell | Julia (every transport step) | [`set_concentrations!`](@ref) / [`get_concentrations!`](@ref) |
| Time and time step | Julia | [`set_time!`](@ref), [`set_time_step!`](@ref) |

## Worked example

```julia
using PhreeqcRM

rm = PhreeqcRMInstance(40)
load_database!(rm, "phreeqc.dat")

# All chemistry — solutions, exchange site capacity, what to record —
# is in the PHREEQC script:
run_string!(rm, \"\"\"
    SOLUTION 0    Inflow water
        units mmol/kgw
        pH 7.0
        Ca 1.0
        Cl 2.0 charge
    SOLUTION 1-40 Initial column water
        units mmol/kgw
        pH 7.0
        Na 1.0
        Cl 1.0 charge
    EXCHANGE 1-40
        -equilibrate 1
        X 0.0011
    SELECTED_OUTPUT 1
        -reset false
        -pH    true
        -totals Na Ca Cl
    END
\"\"\")

# Geometry, time, transport, units — Julia's responsibility:
set_units!(rm; solution = SolutionUnits.KgPerKgSolution)
set_porosity!(rm, fill(0.3, 40))
# ... per-cell setters ...
find_components!(rm)
set_initial_conditions!(rm; solution = collect(1:40), exchange = collect(1:40))
```

The Julia code never names "calcite" or "Gaines-Thomas convention" — those
are entirely the script's concern. The Julia code controls geometry, time,
transport, and result extraction.
