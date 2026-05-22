# Top-level BenchmarkTools SUITE for PhreeqcRM.
#
# Three groups:
#   hot_loop      — per-call timings: set_concentrations!, run_cells!, get_concentrations!
#   threading     — strong-scaling scan over nthreads ∈ {1, 2, 4, 8} for run_cells!
#   allocations   — @allocated per call (should be 0 after warmup)
#
# Per-case benchmarks live in `harness.jl`, which loops over the example
# directories and adds entries for each. A separate `time_c_drivers.jl` script
# times the compiled C drivers and writes `c_timings.json` so we can compute
# the Julia/C overhead ratio in the report.
#
# This file is the entry point used by PkgBenchmark.benchmarkpkg via
# `tune!(SUITE)` and `run(SUITE)`.

using BenchmarkTools
using PhreeqcRM

const SUITE = BenchmarkGroup()
SUITE["hot_loop"]    = BenchmarkGroup()
SUITE["threading"]   = BenchmarkGroup()
SUITE["allocations"] = BenchmarkGroup()

include(joinpath(@__DIR__, "harness.jl"))
