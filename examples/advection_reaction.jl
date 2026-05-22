# 1D advection-reaction column with cation exchange.
#
# Mirrors the canonical PhreeqcRM `advect.pqi` example: 40 cells, single
# inflow boundary, SNIA operator splitting (transport then reaction each step),
# trivial upwind advection on the Julia side and the chemistry done by
# PhreeqcRM. Demonstrates the full end-to-end lifecycle.
#
# Run with:
#   JULIA_PHREEQCRM_PATH="$PWD/deps/usr/lib/libPhreeqcRM.dylib" \
#     julia --project=. examples/advection_reaction.jl

using PhreeqcRM

# ── 1. Resolve the database file shipped with the local libphreeqcrm build ──
const DB = let candidates = [
        joinpath(@__DIR__, "..", "deps", "usr", "share", "doc", "PhreeqcRM", "database", "phreeqc.dat"),
        "/usr/local/share/doc/phreeqc/database/phreeqc.dat",
    ]
    db = nothing
    for c in candidates
        if isfile(c)
            db = c
            break
        end
    end
    db === nothing && error("no phreeqc.dat found; tried $candidates")
    db
end
println("Using database: ", DB)

# ── 2. Chemistry definitions go in PHREEQC's own scripting language ──
const SCRIPT = """
TITLE 1D column with cation exchange
SOLUTION 0   Inflow (Ca-Cl)
    units            mmol/kgw
    pH               7.0     charge
    Ca               1.0
    Cl               2.0
SOLUTION 1-40 Initial column water (Na-saturated)
    units            mmol/kgw
    pH               7.0
    Na               1.0
    Cl               1.0     charge
EXCHANGE 1-40
    -equilibrate     1
    X                0.0011
SELECTED_OUTPUT 1
    -reset           false
    -ph              true
    -totals          Na Ca Cl
END
"""

# ── 3. Build the PhreeqcRM instance ──
const NXYZ = 40
rm = PhreeqcRMInstance(NXYZ; nthreads = 1)
load_database!(rm, DB)
run_string!(rm, SCRIPT)

# Units must match the script's `mmol/kgw` → mol/kgw at the API level.
set_units!(rm; solution = SolutionUnits.KgPerKgSolution)

# Per-cell physical properties — Julia's responsibility, not the script's.
set_porosity!(rm,              fill(0.3, NXYZ))
set_saturation!(rm,            fill(1.0, NXYZ))
set_representative_volume!(rm, fill(1.0, NXYZ))
set_temperature!(rm,           fill(25.0, NXYZ))
set_pressure!(rm,              fill(1.0,  NXYZ))

# Discover components and assign initial reactant blocks to cells.
comps = find_components!(rm)
println("Components ($(length(comps))): ", join(comps, ", "))
set_initial_conditions!(rm;
    solution = collect(1:NXYZ),    # SOLUTION i in cell i
    exchange = collect(1:NXYZ),    # EXCHANGE i in cell i
)

# Boundary concentration: SOLUTION 0 evaluated to component-space.
bc = initial_phreeqc_to_concentrations(rm; solution = [0])
println("Boundary concentrations (size $(size(bc))): ", bc[1, :])

# Allocate the cell × component concentration matrix and fill from initial state.
c = zeros_concentrations(rm)        # (nxyz, ncomps)
get_concentrations!(rm, c)

enable_selected_output!(rm, true)

# ── 4. Time stepping: SNIA operator split (advect → react) ──
const NSTEP  = 120                  # number of transport steps
const DT_S   = 60.0 * 60.0          # 1 hour per step

set_time_step!(rm, DT_S)

"""Upwind advection: cell i takes (1-cfl)*c_i + cfl*c_{i-1} per step.
Cell 1 takes (1-cfl)*c_1 + cfl*bc."""
function upwind!(c::Matrix{Float64}, bc::Matrix{Float64}; cfl::Float64 = 0.9)
    nxyz, _ = size(c)
    # Iterate from the downstream end so we don't overwrite source cells.
    for i in nxyz:-1:2
        @views c[i, :] .= (1 - cfl) .* c[i, :] .+ cfl .* c[i - 1, :]
    end
    @views c[1, :] .= (1 - cfl) .* c[1, :] .+ cfl .* bc[1, :]
    return c
end

for step in 1:NSTEP
    upwind!(c, bc)
    set_concentrations!(rm, c)
    set_time!(rm, step * DT_S)
    run_cells!(rm)
    get_concentrations!(rm, c)
end

# ── 5. Inspect the column at the end of the run ──
out = get_selected_output(rm)
println("\nFinal pH along column:")
for (i, p) in enumerate(out.pH)
    println("  cell $(lpad(i, 2)): pH = $(round(p; digits=3))")
end

println("\nFinal Na (mol/kgw) along column:")
for (i, n) in enumerate(out[Symbol("Na(mol/kgw)")])
    println("  cell $(lpad(i, 2)): Na = $(round(n; sigdigits=4))")
end

println("\nFinal Ca (mol/kgw) along column:")
for (i, ca) in enumerate(out[Symbol("Ca(mol/kgw)")])
    println("  cell $(lpad(i, 2)): Ca = $(round(ca; sigdigits=4))")
end

# Reference values for the integration test in test/test_advect_reference.jl.
const julia_output = c

close(rm)
println("\nAdvection-reaction example finished cleanly.")
