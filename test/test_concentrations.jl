using TestItems

@testitem "Concentration matrix shape is (nxyz, ncomps)" setup=[Fixtures] begin
    using PhreeqcRM
    rm = Fixtures.trivial_rm(8)
    c = zeros_concentrations(rm)
    @test size(c) == (nxyz(rm), ncomps(rm))
    @test size(c) == (8, length(components(rm)))
    @test eltype(c) == Float64
    close(rm)
end

@testitem "Wrong-shape matrix rejected at set_concentrations!" setup=[Fixtures] begin
    using PhreeqcRM
    rm = Fixtures.trivial_rm(8)
    bad = zeros(ncomps(rm), nxyz(rm))    # transposed
    @test_throws DimensionMismatch set_concentrations!(rm, bad)
    close(rm)
end

@testitem "Round-trip at Δt=0 preserves values" setup=[Fixtures] begin
    using PhreeqcRM
    rm = Fixtures.trivial_rm(4)
    c = zeros_concentrations(rm)
    get_concentrations!(rm, c)
    c0 = copy(c)
    set_concentrations!(rm, c)
    set_time_step!(rm, 0.0)
    run_cells!(rm)
    c2 = similar(c)
    get_concentrations!(rm, c2)
    @test c2 ≈ c0 rtol = 1e-10
    close(rm)
end

@testitem "All cells with same initial conditions converge to identical state" setup=[Fixtures] begin
    using PhreeqcRM
    rm = Fixtures.trivial_rm(6)
    c = zeros_concentrations(rm)
    get_concentrations!(rm, c)
    # Every row (each cell) should be the same after equal initial conditions.
    @test all(c[1, :] ≈ c[i, :] for i in 2:nxyz(rm))
    close(rm)
end

@testitem "bycell returns row views (no copy)" setup=[Fixtures] begin
    using PhreeqcRM
    rm = Fixtures.trivial_rm(3)
    c = zeros_concentrations(rm)
    get_concentrations!(rm, c)
    cells = collect(bycell(c))
    @test length(cells) == nxyz(rm)
    @test all(length(v) == ncomps(rm) for v in cells)
    @test cells[1] ≈ c[1, :]
    close(rm)
end

@testitem "Per-cell setters validate length" setup=[Fixtures] begin
    using PhreeqcRM
    rm = PhreeqcRMInstance(10)
    @test_throws DimensionMismatch set_porosity!(rm, fill(0.3, 5))
    @test_throws DimensionMismatch set_saturation!(rm, fill(1.0, 11))
    close(rm)
end
