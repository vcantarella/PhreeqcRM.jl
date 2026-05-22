# API reference

Auto-generated from docstrings.

## Lifecycle

```@docs
PhreeqcRMInstance
PhreeqcRM.with_instance
Base.close(::PhreeqcRMInstance)
PhreeqcRM.open_output!
PhreeqcRM.close_output!
```

## Errors

```@docs
PhreeqcRMError
IRMResult
```

## Database and PHREEQC input

```@docs
load_database!
run_file!
run_string!
```

## Components

```@docs
find_components!
components
ncomps
nxyz
```

## Units

```@docs
set_units!
```

(See also the per-domain enum modules: `SolutionUnits`, `PPAssemblageUnits`,
`ExchangeUnits`, `SurfaceUnits`, `GasPhaseUnits`, `SSAssemblageUnits`,
`KineticsUnits`.)

## Spatial properties

```@docs
set_mapping!
```

The per-cell scalar setters all share the same signature
`f(rm, v::AbstractVector{<:Real})` where `length(v) == nxyz(rm)`. They send
the per-cell physical property to PhreeqcRM's internal store:

- `set_porosity!(rm, v)` — porosity (unitless)
- `set_saturation!(rm, v)` — saturation (unitless)
- `set_representative_volume!(rm, v)` — representative volume (L)
- `set_temperature!(rm, v)` — temperature (°C)
- `set_pressure!(rm, v)` — pressure (atm)
- `set_density!(rm, v)` — density (kg/L)

## Concentrations

```@docs
zeros_concentrations
set_concentrations!
get_concentrations
get_concentrations!
bycell
```

## Initial / boundary conditions

```@docs
set_initial_conditions!
initial_phreeqc_to_concentrations
```

## Time stepping

```@docs
set_time!
set_time_step!
run_cells!
```

## Selected output

```@docs
enable_selected_output!
get_selected_output
selected_output_headings
get_solution_volume
get_density
get_saturation
```

## Threading

```@docs
thread_count
set_thread_count!
```
