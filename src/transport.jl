# Initial / boundary conditions and time stepping.
#
# Initial conditions in PhreeqcRM are an integer table of shape (nxyz, 7) where
# columns 1..7 select which numbered reactant block (from the InitialPhreeqc
# instance) goes into each cell, in the order:
#
#     1: SOLUTION         2: EQUILIBRIUM_PHASES   3: EXCHANGE
#     4: SURFACE          5: GAS_PHASE            6: SOLID_SOLUTIONS
#     7: KINETICS
#
# A value of -1 in any slot means "do not assign this reactant in this cell".
#
# Internally PhreeqcRM expects the flat layout `ic1[cat*nxyz + cell]`. Stored
# column-major in Julia, that's a `Matrix{Cint}(nxyz, 7)` — rows = cells,
# columns = categories — passed via `vec(M)` (zero-copy).

const _IC_COL_NAMES = (:solution, :equilibrium_phases, :exchange,
                       :surface, :gas_phase, :ss_assemblage, :kinetics)

"""
    set_initial_conditions!(rm; solution=fill(-1, nxyz(rm)),
                                equilibrium_phases=..., exchange=...,
                                surface=..., gas_phase=...,
                                ss_assemblage=..., kinetics=...)

Assign numbered reactant blocks (defined in the PHREEQC script previously
loaded with [`run_file!`](@ref)) to each of the `nxyz` cells.

Each keyword takes an integer vector of length `nxyz` — entry `i` is the
PHREEQC user number of the block to use in cell `i`, or `-1` to leave that
slot empty.

Unspecified categories default to `-1` in every cell.
"""
function set_initial_conditions!(rm::PhreeqcRMInstance;
                                solution::AbstractVector{<:Integer} = fill(-1, rm.nxyz),
                                equilibrium_phases::AbstractVector{<:Integer} = fill(-1, rm.nxyz),
                                exchange::AbstractVector{<:Integer} = fill(-1, rm.nxyz),
                                surface::AbstractVector{<:Integer} = fill(-1, rm.nxyz),
                                gas_phase::AbstractVector{<:Integer} = fill(-1, rm.nxyz),
                                ss_assemblage::AbstractVector{<:Integer} = fill(-1, rm.nxyz),
                                kinetics::AbstractVector{<:Integer} = fill(-1, rm.nxyz))
    cats = (solution, equilibrium_phases, exchange, surface,
            gas_phase, ss_assemblage, kinetics)
    for (name, v) in zip(_IC_COL_NAMES, cats)
        length(v) == rm.nxyz ||
            throw(DimensionMismatch("$name length $(length(v)) ≠ nxyz=$(rm.nxyz)"))
    end
    ic1 = Matrix{Cint}(undef, rm.nxyz, 7)
    for (j, v) in enumerate(cats)
        @inbounds for i in 1:rm.nxyz
            ic1[i, j] = Cint(v[i])
        end
    end
    # Pass nothing for the mixing-target IC (no boundary mixing on a basic init).
    _check(Lib.RM_InitialPhreeqc2Module(rm.id, ic1, C_NULL, C_NULL), rm)
    return rm
end

"""
    initial_phreeqc_to_concentrations(rm; solution::AbstractVector{<:Integer}) -> Matrix{Float64}

Translate a list of `SOLUTION N` definitions from the InitialPhreeqc instance
into a concentration matrix of shape `(length(solution), ncomps(rm))` —
same layout convention as [`zeros_concentrations`](@ref): each row is one
boundary solution, each column is one component.

Typical use: build the inflow/boundary concentration vector(s) for transport
without touching any cell:

```julia
bc = initial_phreeqc_to_concentrations(rm; solution=[0])   # SOLUTION 0, 1×ncomps
```
"""
function initial_phreeqc_to_concentrations(rm::PhreeqcRMInstance;
                                          solution::AbstractVector{<:Integer})
    rm.ncomps == 0 && error("call find_components!(rm) before initial_phreeqc_to_concentrations")
    n = length(solution)
    n >= 1 || throw(ArgumentError("provide at least one solution number"))
    bs1 = Vector{Cint}(solution)
    bs2 = fill(Cint(-1), n)            # no mixing
    f1  = fill(Cdouble(1.0), n)        # fraction = 1.0 → use solution1
    c = Matrix{Float64}(undef, n, rm.ncomps)
    _check(Lib.RM_InitialPhreeqc2Concentrations(
        rm.id, c, Cint(n), bs1, bs2, f1), rm)
    return c
end

"""
    set_time!(rm, t::Real)

Set the current simulation time (PhreeqcRM-internal seconds by default).
"""
set_time!(rm::PhreeqcRMInstance, t::Real) =
    (_check(Lib.RM_SetTime(rm.id, Cdouble(t)), rm); rm)

"""
    set_time_step!(rm, dt::Real)

Set the time step over which the next [`run_cells!`](@ref) call will integrate
kinetic reactants. **Must** be called before `run_cells!` or kinetics integrate
over zero time.
"""
set_time_step!(rm::PhreeqcRMInstance, dt::Real) =
    (_check(Lib.RM_SetTimeStep(rm.id, Cdouble(dt)), rm); rm)

"""
    run_cells!(rm)

Run the reaction calculation on every active cell, in parallel across
PhreeqcRM's OpenMP workers. The current cell concentrations are read from
the buffer last seen by [`set_concentrations!`](@ref); the post-reaction
concentrations are stored in PhreeqcRM's internal buffer, retrievable with
[`get_concentrations!`](@ref).
"""
run_cells!(rm::PhreeqcRMInstance) = (_check(Lib.RM_RunCells(rm.id), rm); rm)
