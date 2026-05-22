# Shared fixtures for the @testitem blocks. TestItemRunner discovers
# `@testmodule` (not `@testsetup`) — the API name carried over from older
# TestItems versions doesn't apply here.

using TestItems

@testmodule Fixtures begin
    using PhreeqcRM

    # Resolve a database file: prefer the one shipped with the local libphreeqcrm
    # build, fall back to a system PHREEQC install.
    function database_path()
        for c in [
            joinpath(@__DIR__, "..", "..", "deps", "usr", "share", "doc",
                     "PhreeqcRM", "database", "phreeqc.dat"),
            "/usr/local/share/doc/phreeqc/database/phreeqc.dat",
        ]
            isfile(c) && return c
        end
        error("no phreeqc.dat found for tests")
    end

    """
        trivial_rm(nxyz=10; nthreads=1, with_selected_output=false)

    A minimally-configured `PhreeqcRMInstance` ready for `run_cells!`:
    one NaCl SOLUTION, mol/L units, default per-cell physical properties,
    all `nxyz` cells filled with SOLUTION 1. Returns the instance — the
    caller closes it.
    """
    function trivial_rm(nxyz::Integer = 10;
                        nthreads::Integer = 1,
                        with_selected_output::Bool = false)
        rm = PhreeqcRMInstance(nxyz; nthreads)
        load_database!(rm, database_path())
        script = """
            SOLUTION 1
                pH 7.0
                Na 1.0
                Cl 1.0 charge
            $(with_selected_output ? "SELECTED_OUTPUT 1\n    -reset false\n    -ph true\n    -totals Na Cl" : "")
            END
        """
        run_string!(rm, script)
        set_units!(rm; solution = SolutionUnits.MolPerL)
        set_porosity!(rm,              fill(0.3, nxyz))
        set_saturation!(rm,            fill(1.0, nxyz))
        set_representative_volume!(rm, fill(1.0, nxyz))
        set_temperature!(rm,           fill(25.0, nxyz))
        set_pressure!(rm,              fill(1.0,  nxyz))
        find_components!(rm)
        set_initial_conditions!(rm; solution = fill(1, nxyz))
        with_selected_output && enable_selected_output!(rm, true)
        set_time!(rm, 0.0)
        set_time_step!(rm, 1.0)
        return rm
    end
end

