# SELECTED_OUTPUT retrieval.
#
# The PHREEQC script defines a `SELECTED_OUTPUT N` block (and/or `USER_PUNCH`)
# listing what numerical quantities to record per cell. PhreeqcRM accumulates
# those values into an internal nrows × ncols table on every `run_cells!`.
#
# Column headings are queried once on first call and cached on the instance.

"""
    enable_selected_output!(rm, on::Bool)

Turn the recording of `SELECTED_OUTPUT` columns on or off. Defaults to off in
the upstream library. Call before [`run_cells!`](@ref) to get fresh values
out of [`get_selected_output`](@ref).
"""
function enable_selected_output!(rm::PhreeqcRMInstance, on::Bool)
    _check(Lib.RM_SetSelectedOutputOn(rm.id, Cint(on ? 1 : 0)), rm)
    return rm
end

"""
    selected_output_headings(rm) -> Vector{String}

Column names from the `SELECTED_OUTPUT` block. Cached on first call.
"""
function selected_output_headings(rm::PhreeqcRMInstance)
    isempty(rm.selected_output_headings) || return rm.selected_output_headings
    ncols = Int(Lib.RM_GetSelectedOutputColumnCount(rm.id))
    ncols < 0 && throw(PhreeqcRMError(IRMResult(Cint(-7)), _error_message(rm.id)))
    headings = String[]
    sizehint!(headings, ncols)
    buf = Vector{UInt8}(undef, 100)
    for j in 0:(ncols - 1)
        rc = GC.@preserve buf @ccall Lib.libphreeqcrm.RM_GetSelectedOutputHeading(
            rm.id::Cint, Cint(j)::Cint, pointer(buf)::Ptr{UInt8},
            Cint(length(buf))::Cint)::Cint
        _check(rc, rm)
        push!(headings, strip(GC.@preserve buf unsafe_string(pointer(buf))))
    end
    rm.selected_output_headings = headings
    return headings
end

"""
    get_selected_output(rm) -> NamedTuple

Return the current `SELECTED_OUTPUT` table as a `NamedTuple` whose names are
the column headings (as `Symbol`s) and whose values are `Vector{Float64}` of
length `RM_GetSelectedOutputRowCount(rm)` (which equals `nxyz` when the
selected output is per cell).

Allocates. Use [`get_selected_output!`](@ref) for hot paths.
"""
function get_selected_output(rm::PhreeqcRMInstance)
    headings = selected_output_headings(rm)
    ncols = length(headings)
    nrows = Int(Lib.RM_GetSelectedOutputRowCount(rm.id))
    # Internal storage: column-major Julia of shape (nrows, ncols) matches
    # PhreeqcRM's cell-fastest layout `so[i_col*nrows + i_row]` byte-for-byte
    # (same convention as concentrations). Each row = one cell, each column =
    # one output heading.
    so = Matrix{Float64}(undef, nrows, ncols)
    _check(Lib.RM_GetSelectedOutput(rm.id, so), rm)
    cols = ntuple(j -> Vector{Float64}(view(so, :, j)), ncols)
    return NamedTuple{Tuple(Symbol.(headings))}(cols)
end

"""
    get_selected_output!(rm, so::Matrix{Float64}) -> Matrix{Float64}

In-place form of [`get_selected_output`](@ref). `so` must be sized
`(RM_GetSelectedOutputRowCount(rm), length(selected_output_headings(rm)))`.
Each *row* of `so` holds one cell's output values across all headings.
"""
function get_selected_output!(rm::PhreeqcRMInstance, so::Matrix{Float64})
    ncols = length(selected_output_headings(rm))
    nrows = Int(Lib.RM_GetSelectedOutputRowCount(rm.id))
    size(so) == (nrows, ncols) ||
        throw(DimensionMismatch("selected output buffer must be size ($nrows, $ncols), got $(size(so))"))
    _check(Lib.RM_GetSelectedOutput(rm.id, so), rm)
    return so
end

"""
    get_solution_volume(rm) -> Vector{Float64}

Per-cell solution volume (L) after the most recent [`run_cells!`](@ref).
"""
function get_solution_volume(rm::PhreeqcRMInstance)
    v = Vector{Float64}(undef, rm.nxyz)
    _check(Lib.RM_GetSolutionVolume(rm.id, v), rm)
    return v
end

"""
    get_density(rm) -> Vector{Float64}

Per-cell solution density (kg/L) computed from the most recent
[`run_cells!`](@ref).
"""
function get_density(rm::PhreeqcRMInstance)
    d = Vector{Float64}(undef, rm.nxyz)
    _check(Lib.RM_GetDensityCalculated(rm.id, d), rm)
    return d
end

"""
    get_saturation(rm) -> Vector{Float64}

Per-cell saturation (unitless) computed from the most recent
[`run_cells!`](@ref) — may differ from the value last passed to
[`set_saturation!`](@ref) if mineral dissolution / precipitation changed the
solution volume.
"""
function get_saturation(rm::PhreeqcRMInstance)
    s = Vector{Float64}(undef, rm.nxyz)
    _check(Lib.RM_GetSaturationCalculated(rm.id, s), rm)
    return s
end
