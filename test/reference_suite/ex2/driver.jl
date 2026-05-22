# Julia driver for ex2 — batch parameter sweep over temperature.
#
# The PHREEQC script uses REACTION_TEMPERATURE to step through 51
# temperatures (25 → 75 °C) and records the saturation index of gypsum and
# anhydrite at each temperature. PhreeqcRM doesn't execute
# REACTION_TEMPERATURE directly, but the script's intent maps cleanly to
# an *array of batch reactors* — 51 cells, each at a different temperature,
# all carrying SOLUTION 1 + EQUILIBRIUM_PHASES 1.

module Ex2Driver

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

# 51 temperatures from 25 to 75 °C (exactly what REACTION_TEMPERATURE 1 emits).
const TEMPS = collect(range(25.0, 75.0; length = 51))
const NXYZ  = length(TEMPS)

# Chemistry definitions: same SOLUTION 1, EQUILIBRIUM_PHASES 1, and
# SELECTED_OUTPUT block as the upstream ex2. The reactant block is now used
# per cell rather than per REACTION_TEMPERATURE step.
const CHEMISTRY = """
SOLUTION 1 Pure water
    pH      7.0
    temp    25.0
EQUILIBRIUM_PHASES 1
    Gypsum     0.0  1.0
    Anhydrite  0.0  1.0
SELECTED_OUTPUT 1
    -reset       true
    -temperature true
    -si          anhydrite  gypsum
END
"""

function setup_ex2()
    rm = PhreeqcRMInstance(NXYZ; nthreads = 1)
    load_database!(rm, _database())
    run_string!(rm, CHEMISTRY)
    set_units!(rm; solution = SolutionUnits.MolPerL)
    set_porosity!(rm,              fill(1.0, NXYZ))
    set_saturation!(rm,            fill(1.0, NXYZ))
    set_representative_volume!(rm, fill(1.0, NXYZ))
    set_pressure!(rm,              fill(1.0, NXYZ))
    find_components!(rm)
    set_initial_conditions!(rm;
        solution = fill(1, NXYZ),
        equilibrium_phases = fill(1, NXYZ),
    )
    # Override per-cell temperature AFTER the initial-condition assignment so
    # SOLUTION 1's default temp (25 °C) doesn't win on every cell.
    set_temperature!(rm, TEMPS)
    enable_selected_output!(rm, true)
    set_time!(rm, 0.0); set_time_step!(rm, 0.0)
    return rm
end

"Run all 51 equilibrations, return NamedTuple of selected output columns."
function collect_run()
    rm = setup_ex2()
    try
        run_cells!(rm)
        return get_selected_output(rm)
    finally
        close(rm)
    end
end

end # module Ex2Driver
