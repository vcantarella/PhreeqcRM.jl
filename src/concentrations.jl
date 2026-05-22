# Concentration matrix I/O and the per-cell setters.
#
# CRITICAL LAYOUT NOTE
# --------------------
# PhreeqcRM stores the concentration buffer with the CELL index varying
# fastest and the COMPONENT index varying slowest. Verified empirically:
#
#     buf[i_cell + nxyz * i_comp]
#
# (C-side it's a row-major (ncomps, nxyz) buffer; component is the outer axis.)
#
# Julia is column-major. A `Matrix{Float64}(nxyz, ncomps)` has linear order
#
#     mem[r-1 + nrows*(c-1)]   with nrows = nxyz
#
# which matches PhreeqcRM's layout exactly — so `pointer(M)` is usable
# directly with zero copying. Each ROW is one cell; each COLUMN is one
# component across all cells. Reversing the shape silently scrambles
# data across cells.
#
# `zeros_concentrations(rm)` returns the correct shape; the setters and
# getters validate it.

"""
    set_mapping!(rm, grid2chem::AbstractVector{<:Integer})

Map each of `nxyz` transport cells to a reaction cell index. `-1` marks an
inactive transport cell that should not be reacted. Default mapping is
identity (`collect(0:nxyz-1)`); call this only if you need to skip cells or
collapse multiple transport cells onto one reaction cell.
"""
function set_mapping!(rm::PhreeqcRMInstance, grid2chem::AbstractVector{<:Integer})
    length(grid2chem) == rm.nxyz ||
        throw(DimensionMismatch("mapping length $(length(grid2chem)) ≠ nxyz=$(rm.nxyz)"))
    arr = Vector{Cint}(grid2chem)
    _check(Lib.RM_CreateMapping(rm.id, arr), rm)
    return rm
end

# Each per-cell scalar setter validates length and calls the underlying RM_Set*.
for (jl, c_fn) in (
        (:set_porosity!,              :RM_SetPorosity),
        (:set_saturation!,            :RM_SetSaturationUser),
        (:set_representative_volume!, :RM_SetRepresentativeVolume),
        (:set_temperature!,           :RM_SetTemperature),
        (:set_pressure!,              :RM_SetPressure),
        (:set_density!,               :RM_SetDensityUser),
    )
    @eval function $jl(rm::PhreeqcRMInstance, v::AbstractVector{<:Real})
        length(v) == rm.nxyz ||
            throw(DimensionMismatch("expected length nxyz=$(rm.nxyz), got $(length(v))"))
        arr = v isa Vector{Cdouble} ? v : Vector{Cdouble}(v)
        _check(Lib.$c_fn(rm.id, arr), rm)
        return rm
    end
end

"""
    set_units!(rm; solution, pp_assemblage=..., exchange=..., surface=...,
               gas_phase=..., ss_assemblage=..., kinetics=...)

Configure the unit convention for each reactant category. `solution` is
required — its value determines how the numbers passed to
[`set_concentrations!`](@ref) are interpreted (mg/L vs mol/L vs kg/kgs).

All `*_assemblage` / `exchange` / `surface` / `gas_phase` / `kinetics` units
default to mol/L of rock volume.

Each keyword takes a value from the matching enum: `SolutionUnits.MolPerL`,
`PPAssemblageUnits.MolPerLRock`, etc.
"""
function set_units!(rm::PhreeqcRMInstance;
                   solution::SolutionUnits.T,
                   pp_assemblage::PPAssemblageUnits.T = PPAssemblageUnits.MolPerLRock,
                   exchange::ExchangeUnits.T = ExchangeUnits.MolPerLRock,
                   surface::SurfaceUnits.T = SurfaceUnits.MolPerLRock,
                   gas_phase::GasPhaseUnits.T = GasPhaseUnits.MolPerLRock,
                   ss_assemblage::SSAssemblageUnits.T = SSAssemblageUnits.MolPerLRock,
                   kinetics::KineticsUnits.T = KineticsUnits.MolPerLRock)
    _check(Lib.RM_SetUnitsSolution(rm.id, Cint(Integer(solution))), rm)
    _check(Lib.RM_SetUnitsPPassemblage(rm.id, Cint(Integer(pp_assemblage))), rm)
    _check(Lib.RM_SetUnitsExchange(rm.id, Cint(Integer(exchange))), rm)
    _check(Lib.RM_SetUnitsSurface(rm.id, Cint(Integer(surface))), rm)
    _check(Lib.RM_SetUnitsGasPhase(rm.id, Cint(Integer(gas_phase))), rm)
    _check(Lib.RM_SetUnitsSSassemblage(rm.id, Cint(Integer(ss_assemblage))), rm)
    _check(Lib.RM_SetUnitsKinetics(rm.id, Cint(Integer(kinetics))), rm)
    return rm
end

"""
    zeros_concentrations(rm) -> Matrix{Float64}

Allocate a fresh concentration matrix sized `(nxyz(rm), ncomps(rm))`, initialized
to zero. This is the recommended constructor — passing the wrong shape to
[`set_concentrations!`](@ref) is an error, but constructing this way makes the
contract self-enforcing.

Each **row** holds one cell; each **column** holds one component across cells.
"""
function zeros_concentrations(rm::PhreeqcRMInstance)
    rm.ncomps == 0 && error("call find_components!(rm) before zeros_concentrations()")
    return zeros(Float64, rm.nxyz, rm.ncomps)
end

_check_conc_shape(rm::PhreeqcRMInstance, c::AbstractMatrix) =
    size(c) == (rm.nxyz, rm.ncomps) ||
        throw(DimensionMismatch(
            "concentration matrix must be size (nxyz, ncomps) = $(( rm.nxyz, rm.ncomps )), got $(size(c))"))

# Accept anything that's stride-compatible and Float64. Contiguous layout —
# strided slices like view(M, :, 2:end-1) (a column range of a column-major
# matrix) are contiguous in memory; view(M, 1:5, :) is not.
const ConcMatrix = StridedMatrix{Float64}

function _check_conc_contig(c::AbstractMatrix{Float64})
    st = strides(c)
    st == (1, size(c, 1)) || throw(ArgumentError(
        "concentration matrix must be contiguous (strides == (1, size(c,1))), got strides=$st"))
end

"""
    set_concentrations!(rm, c::AbstractMatrix{Float64})

Send the per-cell, per-component concentrations to PhreeqcRM. `c` must have
shape `(nxyz(rm), ncomps(rm))` and contiguous strides — the recommended way
to allocate it is [`zeros_concentrations`](@ref). Validated, zero-copy in the
happy path.
"""
function set_concentrations!(rm::PhreeqcRMInstance, c::AbstractMatrix{Float64})
    rm.ncomps == 0 && error("call find_components!(rm) before set_concentrations!")
    _check_conc_shape(rm, c)
    _check_conc_contig(c)
    _check(Lib.RM_SetConcentrations(rm.id, c), rm)
    return rm
end

"""
    get_concentrations!(rm, c::AbstractMatrix{Float64})

Pull the post-reaction concentrations from PhreeqcRM into the caller's buffer
`c`. Shape and contiguity requirements match [`set_concentrations!`](@ref).
**In-place** — does not allocate. This is what the hot loop should use.
"""
function get_concentrations!(rm::PhreeqcRMInstance, c::AbstractMatrix{Float64})
    rm.ncomps == 0 && error("call find_components!(rm) before get_concentrations!")
    _check_conc_shape(rm, c)
    _check_conc_contig(c)
    _check(Lib.RM_GetConcentrations(rm.id, c), rm)
    return c
end

"""
    get_concentrations(rm) -> Matrix{Float64}

Allocating convenience that returns a fresh `Matrix{Float64}(ncomps, nxyz)`
filled with current concentrations. Do **not** call inside a hot loop — use
[`get_concentrations!`](@ref) with a pre-allocated buffer instead.
"""
function get_concentrations(rm::PhreeqcRMInstance)
    c = zeros_concentrations(rm)
    return get_concentrations!(rm, c)
end

"""
    bycell(c::AbstractMatrix{Float64})

Iterator over per-cell row views of a concentration matrix `(nxyz, ncomps)`.
Each element is a `view` (no copy) of length `ncomps`. Convenient for
per-cell inspection:

```julia
for (icell, cell) in enumerate(bycell(c))
    @show icell, cell[1]   # first component in this cell
end
```
"""
bycell(c::AbstractMatrix{Float64}) = eachrow(c)
