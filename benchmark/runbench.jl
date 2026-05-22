# Benchmark entry point.
#
# Usage:
#   julia --project=benchmark benchmark/runbench.jl
#   julia --project=benchmark benchmark/runbench.jl --tier=quick
#
# `--tier=quick` skips the threading scan and the 1000-cell case so the entire
# run finishes in ≤ 90 s (the PR-gate budget). `--tier=full` (default) runs
# everything in `benchmarks.jl`.

using Pkg
Pkg.activate(@__DIR__)

using BenchmarkTools
using Statistics
import JSON3

const HERE = @__DIR__
const ROOT = joinpath(HERE, "..")

include(joinpath(HERE, "benchmarks.jl"))      # defines SUITE
include(joinpath(HERE, "plots.jl"))

# ── argument parsing ──
tier = :full
for a in ARGS
    a == "--tier=quick" && (tier = :quick)
    a == "--tier=full"  && (tier = :full)
end

# Trim the suite for quick tier — keep only nxyz=40 hot-loop entries and allocs.
if tier === :quick
    delete!(SUITE, "threading")
    let h = SUITE["hot_loop"]
        for k in collect(keys(h))
            occursin("nxyz=1000", String(k)) && delete!(h, k)
        end
    end
    @info "Quick tier: stripped threading scan and nxyz=1000 entries"
end

# ── tune (one-off; cache to params.json) ──
const PARAMS = joinpath(HERE, "params.json")
if isfile(PARAMS)
    loadparams!(SUITE, BenchmarkTools.load(PARAMS)[1], :evals, :samples)
    @info "Loaded tuning from $(basename(PARAMS))"
else
    @info "Tuning suite (first run only)..."
    tune!(SUITE)
    BenchmarkTools.save(PARAMS, params(SUITE))
end

# ── measure ──
@info "Running benchmark suite (tier=$tier)..."
results = run(SUITE; verbose = true)

# Persist
LATEST = joinpath(HERE, "latest.json")
BenchmarkTools.save(LATEST, median(results))
@info "Wrote $LATEST"

# ── C-driver timings, if a sidecar JSON exists ──
const C_TIMINGS_FILE = joinpath(HERE, "c_timings.json")
c_timings = Dict{String, Float64}()
if isfile(C_TIMINGS_FILE)
    raw = JSON3.read(read(C_TIMINGS_FILE, String))
    for (k, v) in pairs(raw)
        c_timings[String(k)] = Float64(v)
    end
end

# ── plots ──
plots_dir = joinpath(HERE, "plots")
mkpath(plots_dir)
plot_hot_loop_per_case(joinpath(plots_dir, "hot_loop"), results)
plot_threading_scaling(joinpath(plots_dir, "threading_scaling.png"), results)
plot_allocations_bars(joinpath(plots_dir, "allocations.png"), results)
plot_julia_vs_c_overhead(joinpath(plots_dir, "overhead_summary.png"),
                         results, c_timings)
@info "Plots written to $plots_dir"

# ── regression check against baseline (per Julia version) ──
julia_tag = "v$(VERSION.major).$(VERSION.minor)"
baseline_path = joinpath(HERE, "baseline", "$(julia_tag).json")
if isfile(baseline_path)
    baseline = BenchmarkTools.load(baseline_path)[1]
    judgement = judge(median(results), baseline;
                      time_tolerance = 0.05, memory_tolerance = 0.0)
    BenchmarkTools.save(joinpath(HERE, "judge_$(julia_tag).json"), judgement)
    open(joinpath(HERE, "judge_summary.md"), "w") do io
        export_markdown(io, judgement)
    end
    leaves_vec = leaves(judgement)
    regressions = filter(p -> any(t -> t == :regression, values(p[2].time)),
                         leaves_vec)
    if !isempty(regressions)
        @error "Regressions detected vs baseline $(basename(baseline_path)):"
        for (k, v) in regressions
            @error "  $(join(k, '/'))" judgement = v
        end
        exit(1)
    end
    @info "No regressions vs $(basename(baseline_path)) (tolerance 5%, mem 0%)"
else
    @info "No baseline at $baseline_path — skipping regression check. " *
          "First run; commit `latest.json` as the baseline once happy."
end

@info "Benchmark run complete."
