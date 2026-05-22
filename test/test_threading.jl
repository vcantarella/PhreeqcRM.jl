using TestItems

@testitem "OMP thread count is honored" tags=[:threads] begin
    using PhreeqcRM
    rm1 = PhreeqcRMInstance(8; nthreads = 1)
    @test thread_count(rm1) == 1
    close(rm1)
    # If the runner has at least 2 cores we should be able to ask for 2 OMP threads.
    if Sys.CPU_THREADS >= 2
        rm2 = PhreeqcRMInstance(8; nthreads = 2)
        @test thread_count(rm2) == 2
        close(rm2)
    end
end

@testitem "Two instances driven from two Julia threads agree with serial" tags=[:threads] setup=[Fixtures] begin
    using PhreeqcRM
    Threads.nthreads() >= 2 || return       # skip on single-threaded runs
    rm_par = [Fixtures.trivial_rm(16; nthreads = 1) for _ in 1:2]
    rm_ref = Fixtures.trivial_rm(16; nthreads = 1)

    results = Vector{Matrix{Float64}}(undef, 2)
    Threads.@threads for i in 1:2
        rm = rm_par[i]
        c = zeros_concentrations(rm)
        get_concentrations!(rm, c)
        set_concentrations!(rm, c)
        run_cells!(rm)
        get_concentrations!(rm, c)
        results[i] = c
    end
    c_ref = zeros_concentrations(rm_ref)
    get_concentrations!(rm_ref, c_ref)
    set_concentrations!(rm_ref, c_ref)
    run_cells!(rm_ref)
    get_concentrations!(rm_ref, c_ref)

    @test results[1] ≈ c_ref rtol = 1e-10
    @test results[2] ≈ c_ref rtol = 1e-10
    foreach(close, rm_par); close(rm_ref)
end

@testitem "Oversubscription warns" tags=[:threads] begin
    using PhreeqcRM
    Threads.nthreads() >= 2 || return
    @test_warn r"oversubscription"i PhreeqcRMInstance(4; nthreads = Sys.CPU_THREADS)
end
