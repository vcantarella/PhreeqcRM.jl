# Database loading, PHREEQC script execution, and component discovery.

"""
    load_database!(rm, path::AbstractString)

Read a PHREEQC database file (e.g. `phreeqc.dat`, `llnl.dat`, `pitzer.dat`)
into all the IPhreeqc instances inside `rm`. **Must** precede [`run_file!`](@ref).
"""
function load_database!(rm::PhreeqcRMInstance, path::AbstractString)
    isfile(path) || throw(ArgumentError("Database file not found: $path"))
    _check(Lib.RM_LoadDatabase(rm.id, String(path)), rm)
    return rm
end

"""
    run_file!(rm, path; workers=true, initial=true, utility=true)

Run a PHREEQC input file against the selected IPhreeqc instances inside `rm`.

  - `workers=true`  — populate the worker IPhreeqc instances (the ones that
    do per-cell chemistry inside `run_cells!`).
  - `initial=true`  — populate the InitialPhreeqc instance, which holds the
    numbered `SOLUTION` / `EXCHANGE` / `EQUILIBRIUM_PHASES` definitions later
    referenced by [`set_initial_conditions!`](@ref).
  - `utility=true`  — populate the Utility instance.

The defaults match the common case: a PHREEQC script that defines the full
chemistry. Call once before [`find_components!`](@ref).
"""
function run_file!(rm::PhreeqcRMInstance, path::AbstractString;
                  workers::Bool = true, initial::Bool = true, utility::Bool = true)
    isfile(path) || throw(ArgumentError("Input file not found: $path"))
    _check(Lib.RM_RunFile(rm.id,
                          Cint(workers), Cint(initial), Cint(utility),
                          String(path)), rm)
    return rm
end

"""
    run_string!(rm, input; workers=true, initial=true, utility=true)

Same as [`run_file!`](@ref) but takes a PHREEQC input as a string. Useful for
programmatically generated scripts or inline test fixtures.
"""
function run_string!(rm::PhreeqcRMInstance, input::AbstractString;
                    workers::Bool = true, initial::Bool = true, utility::Bool = true)
    _check(Lib.RM_RunString(rm.id,
                            Cint(workers), Cint(initial), Cint(utility),
                            String(input)), rm)
    return rm
end

"""
    find_components!(rm) -> Vector{String}

Scan the InitialPhreeqc instance for every element / mass-balance component
that has been defined by [`run_file!`](@ref) / [`run_string!`](@ref), and
cache the result on `rm`.

**Must be called before any [`set_concentrations!`](@ref) /
[`get_concentrations!`](@ref) call** because the concentration buffer is sized
`ncomps(rm) * nxyz(rm)`. Subsequent calls are cheap (results are cached).
"""
function find_components!(rm::PhreeqcRMInstance)
    n = Lib.RM_FindComponents(rm.id)
    n < 0 && throw(PhreeqcRMError(IRMResult(n), _error_message(rm.id)))
    rm.ncomps = Int(n)
    rm.components = String[]
    sizehint!(rm.components, n)
    buf = Vector{UInt8}(undef, 100)
    for i in 0:(n - 1)
        # Clang.jl typed the output char* as Cstring, but it's actually a
        # caller-allocated buffer. Bypass via @ccall and a UInt8 pointer.
        rc = GC.@preserve buf @ccall Lib.libphreeqcrm.RM_GetComponent(
            rm.id::Cint, Cint(i)::Cint, pointer(buf)::Ptr{UInt8},
            Cint(length(buf))::Cint)::Cint
        _check(rc, rm)
        push!(rm.components, GC.@preserve buf unsafe_string(pointer(buf)))
    end
    return rm.components
end

"""
    components(rm) -> Vector{String}

Cached component names from the most recent [`find_components!`](@ref).
Throws if [`find_components!`](@ref) hasn't been called yet.
"""
function components(rm::PhreeqcRMInstance)
    rm.ncomps == 0 && error("call find_components!(rm) before accessing components()")
    return rm.components
end

"""
    ncomps(rm) -> Int

Number of components in `rm`'s chemistry. Zero until [`find_components!`](@ref)
is called.
"""
ncomps(rm::PhreeqcRMInstance) = rm.ncomps

"""
    nxyz(rm) -> Int

Number of reaction cells in `rm` (the value passed to the constructor).
"""
nxyz(rm::PhreeqcRMInstance) = rm.nxyz
