# Memory model & array layout

PhreeqcRM never returns malloc'd memory the caller has to free. Every array
crossing the boundary is **caller-allocated** on both sides of the call:

| Pattern | Who allocates | Who fills | Examples |
|---|---|---|---|
| Caller-allocated, callee-reads  | caller | library copies into its internal store | [`set_porosity!`](@ref), [`set_concentrations!`](@ref) |
| Caller-allocated, callee-writes | caller | library writes into the buffer         | [`get_concentrations!`](@ref), [`get_selected_output`](@ref), error strings |

## Concentration matrix layout

The library packs the concentration buffer with the **cell index varying
fastest** and the component index slowest:

```
buf[i_cell + nxyz * i_comp]    // C-side
```

The Julia shape that matches this with zero copying is **`Matrix{Float64}(nxyz, ncomps)`**:

- Each **row** is one cell.
- Each **column** is one component across all cells.
- `vec(M)` produces the byte layout PhreeqcRM expects with **no allocation**.

Use [`zeros_concentrations`](@ref) to construct the right shape:

```julia
c = zeros_concentrations(rm)                   # Matrix{Float64}(nxyz(rm), ncomps(rm))
get_concentrations!(rm, c)                     # zero-copy
```

`set_concentrations!` and `get_concentrations!` validate the shape on every
call. Passing the transposed shape would silently scramble data across cells
— so the validator throws `DimensionMismatch`.

## Hot-loop allocation rule

The user's concentration matrix must be allocated **once** outside the time
loop and reused via the in-place setters. The package guarantees zero
allocations per call after warmup; this is asserted in the `:perf` test tier
with `@allocated == 0` on the full step (`set_concentrations!` + `run_cells!`
+ `get_concentrations!`).

```julia
c = zeros_concentrations(rm)        # allocate ONCE
get_concentrations!(rm, c)
for step in 1:nsteps
    transport!(c)
    set_concentrations!(rm, c)
    run_cells!(rm)
    get_concentrations!(rm, c)      # no allocation
end
```

## Boundary / selected-output buffers

Same convention: items vary fastest, categories slowest.

- [`initial_phreeqc_to_concentrations`](@ref) returns a
  `Matrix{Float64}(n_boundaries, ncomps)`. Each row is one boundary solution.
- [`get_selected_output`](@ref) returns a `NamedTuple` of per-column vectors;
  the in-place form takes a `Matrix{Float64}(nrows, ncols)`.
