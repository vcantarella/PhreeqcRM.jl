using TestItems

# These tests pin the hot-path allocation contract: set_concentrations!,
# get_concentrations!, and run_cells! must allocate ZERO bytes after warmup.
# Tagged :perf so they can be run separately when developing.

@testitem "set_concentrations! is allocation-free" tags=[:perf] setup=[Fixtures] begin
    using PhreeqcRM
    rm = Fixtures.trivial_rm(64)
    c = zeros_concentrations(rm)
    set_concentrations!(rm, c)              # warmup (compile + ccall TLS init)
    @test (@allocated set_concentrations!(rm, c)) == 0
    close(rm)
end

@testitem "get_concentrations! is allocation-free" tags=[:perf] setup=[Fixtures] begin
    using PhreeqcRM
    rm = Fixtures.trivial_rm(64)
    c = zeros_concentrations(rm)
    get_concentrations!(rm, c)              # warmup
    @test (@allocated get_concentrations!(rm, c)) == 0
    close(rm)
end

@testitem "run_cells! is allocation-free" tags=[:perf] setup=[Fixtures] begin
    using PhreeqcRM
    rm = Fixtures.trivial_rm(32)
    run_cells!(rm)                          # warmup
    @test (@allocated run_cells!(rm)) == 0
    close(rm)
end

@testitem "Hot-loop step! is allocation-free" tags=[:perf] setup=[Fixtures] begin
    using PhreeqcRM
    rm = Fixtures.trivial_rm(64)
    c = zeros_concentrations(rm)
    get_concentrations!(rm, c)              # initialize with real concentrations
    function step!(rm, c)
        set_concentrations!(rm, c)
        run_cells!(rm)
        get_concentrations!(rm, c)
        return nothing
    end
    step!(rm, c)                            # warmup
    @test (@allocated step!(rm, c)) == 0
    close(rm)
end
