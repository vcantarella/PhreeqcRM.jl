# C vs Julia step-time comparison across the full reference suite.
#
# Three special cases (ex11, ex2, ex9) have hand-written driver.{jl,c} pairs
# exposing a case-specific notion of "step":
#   ex11 — one ADVECTION shift on 40 cells with cation exchange
#   ex2  — one RunCells across a 51-cell temperature sweep
#   ex9  — one kinetic time step on a single cell
#
# Every other case is timed via the GENERIC driver (one `RunCells` call on
# nxyz=1 after the script-derived initial conditions are loaded). The
# generic Julia driver and the generic C driver mirror each other; the
# ratio Julia/C is the pure wrapper overhead.
#
# Output: markdown table on stdout + JSON sidecar at benchmark/c_vs_julia.json
#
# Usage:
#   julia --project=benchmark benchmark/bench_c_vs_julia.jl

using BenchmarkTools
using JSON3
using Printf
using Statistics

const HERE    = @__DIR__
const ROOT    = realpath(joinpath(HERE, ".."))
const C_BUILD = joinpath(ROOT, "test", "c_build")
const SUITE   = joinpath(ROOT, "test", "reference_suite")
const GENERIC_C = joinpath(C_BUILD, "generic_driver")

using PhreeqcRM
include(joinpath(SUITE, "_scripts", "generic_driver.jl"))
include(joinpath(SUITE, "ex11", "driver.jl"))
include(joinpath(SUITE, "ex2",  "driver.jl"))
include(joinpath(SUITE, "ex9",  "driver.jl"))

# Cases the generic driver chokes on (need transport, multi-stage scripts, or
# the system PHREEQC is too old to validate). Smoke-only in numerical tests,
# omitted from the benchmark.
const SKIP_GENERIC = Set([
    "ex11", "ex2", "ex9",          # hand-written drivers (timed separately)
    "ex20b", "ex21",                # known-bad scripts
])

list_cases() = sort(filter(c -> isdir(joinpath(SUITE, c)) && startswith(c, "ex") &&
                              isfile(joinpath(SUITE, c, "input.pqi")),
                          readdir(SUITE)))

function time_c_generic(case::AbstractString, nsteps::Int = 200)
    db = GenericBatchDriver.database_for(joinpath(SUITE, case))
    out = try
        read(`$GENERIC_C --case $case --db $db --root $ROOT --bench $nsteps`, String)
    catch e
        return nothing
    end
    j = try
        JSON3.read(out)
    catch
        return nothing
    end
    return Float64(j["per_step_us"]) * 1e-6
end

function time_julia_generic(case::AbstractString)
    rm = try
        GenericBatchDriver.setup(joinpath(SUITE, case))
    catch
        return nothing
    end
    try
        for _ in 1:5; run_cells!(rm); end
        b = @benchmark run_cells!($rm) samples=100 evals=1 seconds=8
        return median(b.times) * 1e-9
    catch
        return nothing
    finally
        close(rm)
    end
end

function time_c_hand(case, nsteps)
    bin = joinpath(C_BUILD, "$(case)_driver")
    isfile(bin) || return nothing
    raw = read(`$bin --bench $nsteps`, String)
    Float64(JSON3.read(raw)["per_step_us"]) * 1e-6
end

function time_julia_hand(case)
    if case == "ex11"
        state = Ex11Driver.setup_ex11()
        try
            for _ in 1:50; Ex11Driver.step!(state); end
            b = @benchmark Ex11Driver.step!($state) samples=200 evals=1 seconds=10
            median(b.times) * 1e-9
        finally close(state.rm) end
    elseif case == "ex2"
        rm = Ex2Driver.setup_ex2()
        try
            for _ in 1:10; run_cells!(rm); end
            b = @benchmark run_cells!($rm) samples=200 evals=1 seconds=10
            median(b.times) * 1e-9
        finally close(rm) end
    elseif case == "ex9"
        rm = Ex9Driver.setup_ex9()
        try
            set_time!(rm, 0.0); set_time_step!(rm, 100.0)
            for _ in 1:10; run_cells!(rm); end
            ct = Ref(1000.0)
            f = (rm, ct) -> begin
                ct[] += 100.0
                set_time!(rm, ct[]); set_time_step!(rm, 100.0)
                run_cells!(rm)
            end
            b = @benchmark $f($rm, $ct) samples=200 evals=1 seconds=10
            median(b.times) * 1e-9
        finally close(rm) end
    end
end

println("== C vs Julia step-time across the reference suite ==\n")
@printf "%-8s  %-9s  %12s  %12s  %8s  %s\n"  "case" "driver" "C (μs/step)" "Julia (μs/step)" "ratio" "verdict"
println("-" ^ 75)

results = Dict{String, Any}[]
for case in list_cases()
    if case == "ex11" || case == "ex2" || case == "ex9"
        c_step = time_c_hand(case, 1000)
        j_step = time_julia_hand(case)
        driver_kind = "hand"
    elseif case in SKIP_GENERIC
        @printf "%-8s  %-9s  %12s  %12s  %8s  %s\n" case "—" "—" "—" "—" "skipped"
        continue
    else
        c_step = time_c_generic(case, 200)
        j_step = time_julia_generic(case)
        driver_kind = "generic"
    end
    if c_step === nothing || j_step === nothing
        @printf "%-8s  %-9s  %12s  %12s  %8s  %s\n" case driver_kind "—" "—" "—" "no run"
        continue
    end
    ratio = j_step / c_step
    flag = ratio < 1.10 ? "✓"     :
           ratio < 1.25 ? "above" :
                          "***"
    @printf "%-8s  %-9s  %12.2f  %12.2f  %8.3f  %s\n" case driver_kind (c_step * 1e6) (j_step * 1e6) ratio flag
    push!(results, Dict("case" => case, "driver" => driver_kind,
                       "c_per_step_s" => c_step, "julia_per_step_s" => j_step,
                       "ratio" => ratio))
end

open(joinpath(HERE, "c_vs_julia.json"), "w") do io
    JSON3.write(io, results)
end
println("\nSaved $(length(results)) entries to benchmark/c_vs_julia.json")

if !isempty(results)
    rs = [r["ratio"] for r in results]
    @printf "\nWrapper overhead summary: median=%.3f, mean=%.3f, max=%.3f, min=%.3f\n" median(rs) mean(rs) maximum(rs) minimum(rs)
    over_budget = filter(r -> r["ratio"] >= 1.10, results)
    if isempty(over_budget)
        println("All $(length(results)) cases under the 10% overhead budget.")
    else
        println("Above 10% budget ($(length(over_budget))):")
        for r in over_budget
            @printf "  %-8s %.3f\n" r["case"] r["ratio"]
        end
    end
end
