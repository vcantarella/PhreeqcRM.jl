# Julia driver for ex9 — kinetics on a single cell, sequential time stepping.
#
# The PHREEQC script ferrous-iron oxidation with a rate law in the RATES
# block and KINETICS time stepping (11 incremental steps). PhreeqcRM maps
# this cleanly to one cell with sequential set_time_step!/run_cells! calls.
# We extract Fe_di, Fe_tri, pH, SI(Goethite) after each step.
#
# The original script *prefixes* iron with Fe_di / Fe_tri (custom
# SOLUTION_MASTER_SPECIES blocks decouple Fe(II) / Fe(III) so the slow kinetic
# oxidation rate dictates the observed timescale instead of the fast
# thermodynamic Fe redox equilibrium).

module Ex9Driver

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

# 11 incremental time steps in seconds (matches `-steps ...` in KINETICS 1).
const STEPS_S = [100.0, 400.0, 3100.0, 10800.0, 21600.0,
                 5.04e4, 8.64e4, 1.728e5, 1.728e5, 1.728e5, 1.728e5]

# The full chemistry from the script, INCREMENTAL_REACTIONS retained so each
# step adds rather than re-equilibrating from t=0.
function _read_chemistry()
    read(joinpath(HERE, "input.pqi"), String)
end

function setup_ex9()
    rm = PhreeqcRMInstance(1; nthreads = 1)
    load_database!(rm, _database())
    # Run the full script through workers/initial/utility — this parses the
    # custom SOLUTION_MASTER_SPECIES, RATES, KINETICS 1, etc.
    run_string!(rm, _read_chemistry())
    set_units!(rm; solution = SolutionUnits.MolPerL)
    set_porosity!(rm,              [1.0])
    set_saturation!(rm,            [1.0])
    set_representative_volume!(rm, [1.0])
    set_temperature!(rm,           [25.0])
    set_pressure!(rm,              [1.0])
    find_components!(rm)
    # SOLUTION 1 + EQUILIBRIUM_PHASES 1 + KINETICS 1 all defined as user-#1.
    set_initial_conditions!(rm;
        solution = [1],
        equilibrium_phases = [1],
        kinetics = [1],
    )
    enable_selected_output!(rm, true)
    return rm
end

"""Run 11 incremental steps; return Matrix(11, 5) = [time_days, Fe_di, Fe_tri, pH, SI_Goethite]."""
function collect_run()
    rm = setup_ex9()
    out = Matrix{Float64}(undef, length(STEPS_S), 5)
    cumulative_t = 0.0
    try
        for (i, dt) in enumerate(STEPS_S)
            cumulative_t += dt
            set_time!(rm, cumulative_t)
            set_time_step!(rm, dt)
            run_cells!(rm)
            so = get_selected_output(rm)
            # ex9's USER_PUNCH names the columns: Days, Fe(2), Fe(3), pH,
            # si_goethite. The PUNCH expression for `Days` uses SIM_TIME / 86400
            # which inside PhreeqcRM resolves to the step's dt, not the
            # cumulative simulation time (PhreeqcRM resets SIM_TIME per
            # run_cells!). Track cumulative time ourselves.
            out[i, 1] = cumulative_t / 86400.0
            out[i, 2] = so[Symbol("Fe(2)")][1]
            out[i, 3] = so[Symbol("Fe(3)")][1]
            out[i, 4] = so.pH[1]
            out[i, 5] = so.si_goethite[1]
        end
    finally
        close(rm)
    end
    return out
end

end # module Ex9Driver
