using TestItems

@testitem "Create + close lifecycle" begin
    using PhreeqcRM
    rm = PhreeqcRMInstance(10)
    @test isvalid(rm)
    close(rm)
    @test !isvalid(rm)
end

@testitem "Double-close is idempotent" begin
    using PhreeqcRM
    rm = PhreeqcRMInstance(10)
    close(rm); close(rm); close(rm)
    @test !isvalid(rm)
end

@testitem "with_instance closes on success" begin
    using PhreeqcRM
    rm_ref = Ref{Any}(nothing)
    PhreeqcRM.with_instance(5) do rm
        rm_ref[] = rm
        @test isvalid(rm)
    end
    @test !isvalid(rm_ref[])
end

@testitem "with_instance closes on exception" begin
    using PhreeqcRM
    rm_ref = Ref{Any}(nothing)
    @test_throws ErrorException PhreeqcRM.with_instance(5) do rm
        rm_ref[] = rm
        error("boom")
    end
    @test !isvalid(rm_ref[])
end

@testitem "Bad nxyz / nthreads rejected" begin
    using PhreeqcRM
    @test_throws ArgumentError PhreeqcRMInstance(0)
    @test_throws ArgumentError PhreeqcRMInstance(-5)
    @test_throws ArgumentError PhreeqcRMInstance(10; nthreads = 0)
end
