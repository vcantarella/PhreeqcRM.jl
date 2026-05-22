# Threading

PhreeqcRM parallelizes the `RunCells` loop with OpenMP — each OMP thread
runs reactions on its own subset of cells using a dedicated worker
`IPhreeqc`. Julia has its own thread pool. Combining the two naively gives
`nthreads_julia × nthreads_omp` workers contending for cores.

The constructor takes `nthreads` (OpenMP threads) and **defaults to 1** so
you don't accidentally oversubscribe. It also warns if
`Threads.nthreads() * nthreads > Sys.CPU_THREADS`.

## Three patterns

### A — Single instance, OMP for reactions (default)

```julia
rm = PhreeqcRMInstance(nxyz; nthreads = Threads.nthreads())
for step in 1:nsteps
    transport!(c)                    # serial Julia
    set_concentrations!(rm, c)
    set_time!(rm, step*dt); set_time_step!(rm, dt)
    run_cells!(rm)                   # parallel via OpenMP
    get_concentrations!(rm, c)
end
```

Simplest. Best when reactions dominate runtime.

### B — Domain decomposition, multiple instances, Julia threads

```julia
nchunks = Threads.nthreads()
chunks  = collect(Iterators.partition(1:nxyz, cld(nxyz, nchunks)))
rms = [PhreeqcRMInstance(length(c); nthreads = 1) for c in chunks]   # OMP off
# ... per-instance setup ...
cs = [zeros_concentrations(rm) for rm in rms]
for step in 1:nsteps
    transport_with_halo_exchange!(cs, chunks)
    Threads.@threads for i in eachindex(rms)
        set_concentrations!(rms[i], cs[i])
        run_cells!(rms[i])
        get_concentrations!(rms[i], cs[i])
    end
end
```

Better when transport is memory-bound or when you want Julia-thread
parallelism across the full step (not just reactions).

### C — Single instance + Julia threads for I/O

```julia
rm = PhreeqcRMInstance(nxyz; nthreads = max(1, Threads.nthreads() - 1))
out_chan = Channel{NamedTuple}(8)
writer = Threads.@spawn for snap in out_chan; save_to_disk(snap); end

for step in 1:nsteps
    transport!(c)
    set_concentrations!(rm, c); run_cells!(rm); get_concentrations!(rm, c)
    put!(out_chan, get_selected_output(rm))
end
close(out_chan); wait(writer)
```

Useful in production runs where I/O or post-processing would otherwise
serialize behind reactions.

## Safety contract

- **Within one instance**: only one `RM_*` call at a time. PhreeqcRM
  parallelizes `RunCells` internally; firing two `RM_*` calls on the same
  instance from two Julia threads is undefined behavior.
- **Across instances**: independent instances can be driven from independent
  Julia threads concurrently. The `:threads` test tier verifies this — two
  instances driven from two Julia threads produce results matching the
  serial baseline.

## macOS note

macOS clang doesn't ship `omp.h`. The build script installs `libomp` from
Homebrew automatically; without it, the dylib falls back to single-threaded
and `thread_count(rm)` returns `1` regardless of the requested `nthreads`.
