# CairoMakie diagnostic + summary plots for the benchmark suite.
# Used by runbench.jl after a successful run.
#
# All plots write to benchmark/plots/<group>/<entry>.png and the summary
# overhead bar chart goes to benchmark/plots/overhead_summary.png.

using CairoMakie
using BenchmarkTools
using Statistics

"Per-case sample-time histograms."
function plot_hot_loop_per_case(outdir::AbstractString, results::BenchmarkGroup)
    mkpath(outdir)
    hot = results["hot_loop"]
    for (name, trial) in hot
        f = Figure(size = (700, 400))
        med_us = median(trial.times) / 1e3
        ax = Axis(f[1, 1];
                  xlabel = "step time (μs)",
                  ylabel = "samples",
                  title  = "$name\nmedian=$(round(med_us; digits=2)) μs, " *
                           "n=$(length(trial.times)) samples")
        hist!(ax, trial.times ./ 1e3; bins = max(15, length(trial.times) ÷ 5),
              strokecolor = :black, strokewidth = 0.5)
        vlines!(ax, [med_us]; color = :red, linewidth = 2, label = "median")
        axislegend(ax)
        sanitized = replace(string(name), r"[^A-Za-z0-9_]" => "_")
        save(joinpath(outdir, sanitized * ".png"), f)
    end
end

"Strong-scaling curves: speedup vs nthreads, with the ideal line."
function plot_threading_scaling(outpath::AbstractString, results::BenchmarkGroup)
    haskey(results, "threading") || return
    threading = results["threading"]
    isempty(threading) && return
    # Group by case prefix (everything before the last "_n=").
    cases = Dict{String, Dict{Int, Float64}}()
    for (key, trial) in threading
        m = match(r"^(.+)_n=(\d+)$", String(key))
        m === nothing && continue
        case = m.captures[1]
        n    = parse(Int, m.captures[2])
        get!(cases, case, Dict{Int, Float64}())[n] = median(trial.times)
    end
    isempty(cases) && return

    mkpath(dirname(outpath))
    f = Figure(size = (700, 450))
    ax = Axis(f[1, 1];
              xlabel = "nthreads", ylabel = "speedup vs nthreads=1",
              title  = "Strong scaling")
    for (case, times) in cases
        ns = sort(collect(keys(times)))
        ts = [times[n] for n in ns]
        speedup = ts[1] ./ ts
        scatterlines!(ax, ns, speedup; label = case, marker = :circle)
    end
    max_n = maximum(maximum(keys(t)) for t in values(cases))
    lines!(ax, 1:max_n, 1:max_n; color = :gray, linestyle = :dash, label = "ideal")
    axislegend(ax, position = :lt)
    save(outpath, f)
end

"Bar chart of @allocated per case — target is 0 (red bars for anything > 0)."
function plot_allocations_bars(outpath::AbstractString, results::BenchmarkGroup)
    haskey(results, "allocations") || return
    allocs = results["allocations"]
    isempty(allocs) && return
    names = sort(collect(keys(allocs)))
    bytes = [first(allocs[n].times) for n in names]   # @allocated stored in .times
    mkpath(dirname(outpath))
    f = Figure(size = (max(700, 80 * length(names)), 400))
    ax = Axis(f[1, 1];
              xlabel = "case", ylabel = "bytes allocated per step",
              title  = "Allocation budget (target = 0 bytes)",
              xticks = (1:length(names), String.(names)),
              xticklabelrotation = π/4)
    cols = [b == 0 ? :seagreen : :tomato for b in bytes]
    barplot!(ax, 1:length(names), bytes; color = cols)
    save(outpath, f)
end

"Julia/C overhead bar chart. c_timings::Dict{String, Float64} of seconds-per-step."
function plot_julia_vs_c_overhead(outpath::AbstractString,
                                  results::BenchmarkGroup,
                                  c_timings::Dict{String, Float64})
    (haskey(results, "hot_loop") && !isempty(c_timings)) || return
    hot = results["hot_loop"]
    matched = String[]; ratios = Float64[]; j_us = Float64[]; c_us = Float64[]
    for (case, c_sec) in c_timings
        key = "step!__$case"
        # Allow either "step!__<case>" or exact match.
        haskey(hot, key) || continue
        j_med_sec = median(hot[key].times) / 1e9
        push!(matched, case)
        push!(j_us, j_med_sec * 1e6); push!(c_us, c_sec * 1e6)
        push!(ratios, j_med_sec / c_sec)
    end
    isempty(matched) && return
    mkpath(dirname(outpath))
    f = Figure(size = (max(700, 80 * length(matched)), 450))
    ax = Axis(f[1, 1];
              xlabel = "case", ylabel = "Julia / C step time",
              title  = "Wrapper overhead (target < 1.10)",
              xticks = (1:length(matched), matched), xticklabelrotation = π/4)
    cols = [r < 1.10 ? :seagreen : :tomato for r in ratios]
    barplot!(ax, 1:length(matched), ratios; color = cols)
    hlines!(ax, [1.10]; color = :red,  linestyle = :dash, label = "10% budget")
    hlines!(ax, [1.00]; color = :gray, linestyle = :dot,  label = "parity")
    axislegend(ax)
    save(outpath, f)
end
