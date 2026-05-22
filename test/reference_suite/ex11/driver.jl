# Julia driver for ex11 (transport + cation exchange).
#
# Replicates the script's ADVECTION block via the PhreeqcRM cell API + a
# trivial Julia upwind shift. The reference for comparison is the CLI's
# ex11adv.sel output (100 rows, one per shift, punching cell 40).
#
# Used by:
#   - test_reference_suite_numerical.jl   (numerical comparison test)
#   - benchmark/harness_c_vs_julia.jl     (C vs Julia timing)
#
# Exposes:
#   setup_ex11()        → state with rm, c, bc, components, … fields
#   step!(state)        → run one ADVECTION shift (mutates state.c)
#   collect_run(state)  → run 100 shifts, return Matrix(100, 6) matching the reference

module Ex11Driver

using PhreeqcRM

const HERE = @__DIR__
const ROOT = joinpath(HERE, "..", "..", "..")

function _database()
    for c in [joinpath(ROOT, "deps", "usr", "share", "doc", "PhreeqcRM", "database", "phreeqc.dat"),
              "/usr/local/share/doc/phreeqc/database/phreeqc.dat"]
        isfile(c) && return c
    end
    error("phreeqc.dat not found")
end

# The chemistry definitions ex11 needs, minus the TRANSPORT/ADVECTION/
# USER_GRAPH blocks (we drive transport from Julia and don't render graphs).
const CHEMISTRY = """
SOLUTION 0  CaCl2
    units            mmol/kgw
    temp             25.0
    pH               7.0     charge
    pe               12.5    O2(g)   -0.68
    Ca               0.6
    Cl               1.2
SOLUTION 1-40  Initial solution for column
    units            mmol/kgw
    temp             25.0
    pH               7.0     charge
    pe               12.5    O2(g)   -0.68
    Na               1.0
    K                0.2
    N(5)             1.2
EXCHANGE 1-40
    -equilibrate 1
    X                0.0011
END
"""

function setup_ex11()
    rm = PhreeqcRMInstance(40; nthreads = 1)
    load_database!(rm, _database())
    run_string!(rm, CHEMISTRY)
    set_units!(rm; solution = SolutionUnits.MolPerL)
    set_porosity!(rm,              fill(1.0, 40))
    set_saturation!(rm,            fill(1.0, 40))
    set_representative_volume!(rm, fill(1.0, 40))
    set_temperature!(rm,           fill(25.0, 40))
    set_pressure!(rm,              fill(1.0, 40))
    comps = find_components!(rm)
    set_initial_conditions!(rm;
        solution = collect(1:40),
        exchange = collect(1:40),
    )
    # Boundary concentrations from SOLUTION 0 (shape (1, ncomps)).
    bc = initial_phreeqc_to_concentrations(rm; solution = [0])
    # Cell concentration matrix initialized to cell state.
    c = zeros_concentrations(rm)            # (nxyz, ncomps)
    get_concentrations!(rm, c)
    # ADVECTION is plug flow with no dt-dependent reactions in ex11 → dt = 0.
    set_time_step!(rm, 0.0)
    set_time!(rm, 0.0)
    # Indices for the "totals" columns we want to compare:
    #   Na, Cl, K, Ca  (ncomps order is determined by find_components!)
    idx = Dict(name => i for (i, name) in enumerate(comps))
    return (; rm, c, bc, comps, idx)
end

"""ADVECTION shift: cell i ← cell i-1, cell 1 ← boundary; then re-equilibrate."""
function step!(state)
    c, bc = state.c, state.bc
    nxyz = size(c, 1)
    # Shift in reverse so we don't overwrite source rows.
    @inbounds for i in nxyz:-1:2
        @views c[i, :] .= c[i - 1, :]
    end
    @inbounds @views c[1, :] .= bc[1, :]
    set_concentrations!(state.rm, c)
    run_cells!(state.rm)            # re-equilibrate exchanger in each cell
    get_concentrations!(state.rm, c)
    return state
end

"""Run 100 shifts, return Matrix(100, 6) — columns [step, Na, Cl, K, Ca, Pore_vol]."""
function collect_run(state; nsteps::Integer = 100, punch_cell::Integer = 40)
    out = Matrix{Float64}(undef, nsteps, 6)
    iNa = state.idx["Na"]; iCl = state.idx["Cl"]
    iK  = state.idx["K"];  iCa = state.idx["Ca"]
    c = state.c
    for s in 1:nsteps
        step!(state)
        out[s, 1] = Float64(s)
        out[s, 2] = c[punch_cell, iNa]
        out[s, 3] = c[punch_cell, iCl]
        out[s, 4] = c[punch_cell, iK]
        out[s, 5] = c[punch_cell, iCa]
        out[s, 6] = (s + 0.5) / punch_cell
    end
    return out
end

end # module Ex11Driver
