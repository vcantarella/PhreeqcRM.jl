# Thread-count helpers.
#
# PhreeqcRM and Julia have independent thread pools (OpenMP inside the library,
# Julia's task-scheduler threads outside). Naively combining them gives
# `nthreads_julia × nthreads_omp` workers contending for cores.
#
# The constructor takes `nthreads` and warns on oversubscription. These helpers
# expose the current count and let users tweak it after construction.

"""
    thread_count(rm) -> Int

Number of OpenMP threads PhreeqcRM is currently using for the per-cell
reaction loop.
"""
thread_count(rm::PhreeqcRMInstance) = Int(Lib.RM_GetThreadCount(rm.id))

"""
    set_thread_count!(rm, n::Integer)

Change PhreeqcRM's OpenMP thread count after construction. Generally simpler
to set this via the constructor's `nthreads=` keyword.
"""
function set_thread_count!(rm::PhreeqcRMInstance, n::Integer)
    n > 0 || throw(ArgumentError("nthreads must be positive, got $n"))
    # The library exposes SetThreadCount via the C++ class but the C interface
    # historically only exposes it indirectly. If it isn't generated, fall back
    # to a noisy warning rather than silently lying.
    if !isdefined(Lib, :RM_SetThreadCount)
        @warn "RM_SetThreadCount is not in the generated C bindings; passing $n is a no-op. \
               Construct the instance with nthreads=$n instead."
        return rm
    end
    _check(getfield(Lib, :RM_SetThreadCount)(rm.id, Cint(n)), rm)
    rm.nthreads = Int(n)
    return rm
end
