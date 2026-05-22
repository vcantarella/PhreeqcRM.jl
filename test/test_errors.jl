using TestItems

@testitem "Bad database path: ArgumentError before any ccall" begin
    using PhreeqcRM
    rm = PhreeqcRMInstance(1)
    @test_throws ArgumentError load_database!(rm, "/no/such/database.dat")
    close(rm)
end

@testitem "Bad initial condition: PhreeqcRMError translated with message" setup=[Fixtures] begin
    using PhreeqcRM
    rm = PhreeqcRMInstance(5)
    load_database!(rm, Fixtures.database_path())
    run_string!(rm, "SOLUTION 1\n pH 7.0\nEND")
    find_components!(rm)
    set_units!(rm; solution = SolutionUnits.MolPerL)
    set_porosity!(rm,              fill(0.3, 5))
    set_saturation!(rm,            fill(1.0, 5))
    set_representative_volume!(rm, fill(1.0, 5))
    set_temperature!(rm,           fill(25.0, 5))
    set_pressure!(rm,              fill(1.0, 5))
    # SOLUTION 999 was never defined — library returns IRM_FAIL with a
    # populated error string.
    err = try
        set_initial_conditions!(rm; solution = fill(999, 5))
        nothing
    catch e
        e
    end
    @test err isa PhreeqcRMError
    @test err.code != PhreeqcRM.LibPhreeqcRM.IRM_OK
    @test occursin("not found", err.message)
    close(rm)
end
