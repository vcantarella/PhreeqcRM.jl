# PhreeqcRMInstance — the high-level handle.
#
# Lifecycle:
#   1. Constructor calls RM_Create (allocates the C++ object + workers) and
#      RM_SetComponentH2O (must precede LoadDatabase). Does NOT open files.
#   2. close(rm) is the documented teardown — calls RM_Destroy and sets a flag
#      so the call is idempotent.
#   3. Finalizer is a safety net that runs close(rm) if the user dropped the
#      handle without closing. Not the primary path: RM_Destroy joins on
#      internal OpenMP threads, which is not something we want firing from
#      arbitrary GC contexts.

"""
    PhreeqcRMInstance(nxyz; nthreads=1, component_h2o=false)

Construct a PhreeqcRM instance covering `nxyz` reaction cells. Returns an
opaque handle around an integer id and a small amount of Julia-side
bookkeeping (no C-owned memory references).

Keyword arguments:

  - `nthreads::Integer=1` — OpenMP thread count for the internal `RunCells`
    loop. The default is `1` to avoid OpenMP × Julia thread oversubscription.
    Set higher (or `Threads.nthreads()`) when reactions dominate runtime.
  - `component_h2o::Bool=false` — if true, water is tracked as its own
    component instead of being inferred from H and O moles. Affects the
    component list reported by [`find_components!`](@ref). **Must** be set
    before [`load_database!`](@ref) — that's why it lives on the constructor.

The constructor does not create any output files. Use [`open_output!`](@ref)
to enable `*.chem.txt` and `*.log.txt` logs.

Always pair with [`Base.close`](@ref) or use [`with_instance`](@ref).
"""
mutable struct PhreeqcRMInstance
    id::Cint
    nxyz::Int
    nthreads::Int
    # Filled by find_components! — 0 means "not yet discovered".
    ncomps::Int
    components::Vector{String}
    # Lifecycle flags
    destroyed::Bool
    selected_output_headings::Vector{String}   # cached on first get_selected_output
end

function PhreeqcRMInstance(nxyz::Integer; nthreads::Integer = 1,
                           component_h2o::Bool = false)
    nxyz > 0 || throw(ArgumentError("nxyz must be positive, got $nxyz"))
    nthreads > 0 || throw(ArgumentError("nthreads must be positive, got $nthreads"))

    # Oversubscription warning — see threading.jl for details.
    nthr_julia = Threads.nthreads()
    if nthr_julia * nthreads > Sys.CPU_THREADS
        @warn """PhreeqcRMInstance: potential thread oversubscription
                 Julia threads ($nthr_julia) × PhreeqcRM OMP threads ($nthreads) = \
                 $(nthr_julia * nthreads) > Sys.CPU_THREADS ($(Sys.CPU_THREADS))."""
    end

    id = Lib.RM_Create(Cint(nxyz), Cint(nthreads))
    id < 0 && error("RM_Create failed (returned $id) — check JULIA_PHREEQCRM_PATH \
                     and that libphreeqcrm is loadable.")

    rm = PhreeqcRMInstance(id, Int(nxyz), Int(nthreads), 0, String[], false, String[])

    # SetComponentH2O must precede LoadDatabase. 0 = false, 1 = true.
    _check(Lib.RM_SetComponentH2O(rm.id, Cint(component_h2o ? 1 : 0)), rm)

    finalizer(_finalize, rm)
    return rm
end

# Finalizer — safety net only. Users should call close(rm) or use with_instance.
function _finalize(rm::PhreeqcRMInstance)
    rm.destroyed && return
    # Best-effort: don't throw from a finalizer.
    try
        Lib.RM_Destroy(rm.id)
    catch
    end
    rm.destroyed = true
    return nothing
end

"""
    close(rm::PhreeqcRMInstance)

Destroy the PhreeqcRM instance and release its OpenMP workers. Idempotent.
"""
function Base.close(rm::PhreeqcRMInstance)
    rm.destroyed && return
    _check(Lib.RM_Destroy(rm.id), rm)
    rm.destroyed = true
    return nothing
end

Base.isvalid(rm::PhreeqcRMInstance) = !rm.destroyed

function Base.show(io::IO, rm::PhreeqcRMInstance)
    state = rm.destroyed ? "destroyed" :
            "id=$(rm.id), nxyz=$(rm.nxyz), nthreads=$(rm.nthreads), ncomps=$(rm.ncomps)"
    print(io, "PhreeqcRMInstance($state)")
end

"""
    with_instance(f, nxyz; kwargs...)

Construct a `PhreeqcRMInstance(nxyz; kwargs...)`, pass it to `f`, and
[`close`](@ref) it on exit — including when `f` throws.

```julia
with_instance(40; nthreads=4) do rm
    load_database!(rm, "phreeqc.dat")
    run_file!(rm, "advect.pqi")
    # ...
end
```
"""
function with_instance(f, nxyz::Integer; kwargs...)
    rm = PhreeqcRMInstance(nxyz; kwargs...)
    try
        return f(rm)
    finally
        close(rm)
    end
end

"""
    open_output!(rm; prefix, dir=pwd())

Open PhreeqcRM's text + log output files at `joinpath(dir, prefix).chem.txt`
and `.log.txt`. Opt-in — the constructor does not create files.
"""
function open_output!(rm::PhreeqcRMInstance;
                     prefix::AbstractString,
                     dir::AbstractString = pwd())
    full = joinpath(dir, String(prefix))
    _check(Lib.RM_SetFilePrefix(rm.id, full), rm)
    _check(Lib.RM_OpenFiles(rm.id), rm)
    return rm
end

"""
    close_output!(rm)

Close any output files previously opened with [`open_output!`](@ref).
"""
function close_output!(rm::PhreeqcRMInstance)
    _check(Lib.RM_CloseFiles(rm.id), rm)
    return rm
end
