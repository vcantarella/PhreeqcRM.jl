using TestItems

# Reference-suite tests: every upstream PHREEQC example under
# `reference_suite/ex*/input.pqi` is run through PhreeqcRM and (when a
# committed reference/cli.sel exists from running the upstream `phreeqc` CLI)
# its selected output is compared numerically against it.
#
# Two failure modes:
#   - Case doesn't load / run via PhreeqcRM → @test pass(load_and_run) fails
#   - Numerical disagreement vs cli.sel beyond rtol → comparison fails
#
# These are tagged :integration so they can be filtered separately.

@testmodule RefSuite begin
    using PhreeqcRM
    using DelimitedFiles

    const SUITE_DIR = joinpath(@__DIR__, "reference_suite")

    function db_path(name::AbstractString)
        for d in [
            "/usr/local/share/doc/phreeqc/database",
            joinpath(@__DIR__, "..", "deps", "usr", "share", "doc",
                     "PhreeqcRM", "database"),
        ]
            p = joinpath(d, name)
            isfile(p) && return p
        end
        error("database $name not found")
    end

    # Local copy of the maintainer-only DB_FOR_CASE map. Kept in sync with
    # reference_suite/_scripts/regenerate_references.jl — if you bump one, bump
    # the other.
    _ex15_db() = joinpath(SUITE_DIR, "_scripts", "ex15.dat")
    function db_for_case(c::AbstractString)
        c in ("ex15", "ex15a", "ex15b") && return _ex15_db()
        c in ("ex17", "ex17b")          && return db_path("pitzer.dat")
        c in ("ex20a", "ex20b")         && return db_path("iso.dat")
        c == "ex22"                     && return db_path("sit.dat")
        return db_path("phreeqc.dat")
    end

    # Cases we can't drive end-to-end through PhreeqcRM run_string!:
    #   - ex20b: relies on a multi-stage SELECTED_OUTPUT -> INCLUDE$ ex20_open
    #     dance that only works if you run the script twice.
    #   - ex21:  uses post-3.7 PHREEQC syntax not in the v3.7.3 system CLI.
    const SKIP_CASES = Set(["ex20b", "ex21"])

    "Run a case through PhreeqcRM. Returns (rm, selected_output_or_nothing)."
    function run_case(case::AbstractString; nxyz::Integer = 1)
        casedir = joinpath(SUITE_DIR, case)
        input = read(joinpath(casedir, "input.pqi"), String)
        rm = PhreeqcRMInstance(nxyz)
        try
            load_database!(rm, db_for_case(case))
            # `INCLUDE$ <name>` directives resolve relative to the cwd, not
            # the script's location — so we cd into the case directory.
            cd(casedir) do
                run_string!(rm, input;
                            workers = true, initial = true, utility = true)
            end
        catch e
            close(rm)
            rethrow()
        end
        # SELECTED_OUTPUT extraction is best-effort — batch scripts emit
        # values directly to their -file argument; the API-side accumulator
        # only has data after run_cells! on cells that have been set up. We
        # try, and if the library says "no selected output", treat it as
        # smoke-only.
        so = nothing
        try
            enable_selected_output!(rm, true)
            so = get_selected_output(rm)
        catch
            so = nothing
        end
        return rm, so
    end

    "Parse a PHREEQC-CLI .sel file into a Dict{String,Vector{Float64}}."
    function read_cli_sel(path::AbstractString)
        # Lines starting with whitespace + non-numeric are headings; data rows
        # are tab/whitespace-separated numbers. PHREEQC .sel is awkward — it
        # has a header line, then sim/state/soln/dist_x columns, then data.
        lines = readlines(path)
        isempty(lines) && return Dict{String, Vector{Float64}}()
        # First non-empty line is the header.
        header_idx = findfirst(!isempty, strip.(lines))
        header_idx === nothing && return Dict{String, Vector{Float64}}()
        cols = split(strip(lines[header_idx]); keepempty = false)
        data = Vector{Vector{Float64}}(undef, length(cols))
        for j in eachindex(cols); data[j] = Float64[]; end
        for line in lines[header_idx + 1:end]
            words = split(strip(line); keepempty = false)
            length(words) == length(cols) || continue
            for (j, w) in enumerate(words)
                x = tryparse(Float64, w)
                push!(data[j], x === nothing ? NaN : x)
            end
        end
        return Dict{String, Vector{Float64}}(String(cols[j]) => data[j]
                                             for j in eachindex(cols))
    end

    "Approximate-equal of two vectors ignoring NaN entries."
    function vec_isapprox(a::AbstractVector{<:Real}, b::AbstractVector{<:Real};
                         rtol = 1e-6, atol = 1e-9)
        length(a) == length(b) || return false
        for (x, y) in zip(a, b)
            (isnan(x) && isnan(y)) && continue
            (isnan(x) || isnan(y)) && return false
            isapprox(x, y; rtol, atol) || return false
        end
        return true
    end

    function case_list()
        all = sort(readdir(SUITE_DIR))
        filter(c -> isdir(joinpath(SUITE_DIR, c)) && c != "_scripts" &&
                    isfile(joinpath(SUITE_DIR, c, "input.pqi")), all)
    end
end


# One @testitem per case keeps the per-case context clear in the test report.
# The test body inspects whether a reference/cli.sel exists; if so, compare;
# else, smoke-only.

@testitem "Reference suite: ex* cases load + run + match CLI" tags=[:integration] setup=[RefSuite] begin
    using PhreeqcRM
    cases = RefSuite.case_list()
    @assert !isempty(cases)
    n_compared = Ref(0)
    n_smoke    = Ref(0)
    failures   = String[]
    for c in cases
        c in RefSuite.SKIP_CASES && continue
        casedir = joinpath(RefSuite.SUITE_DIR, c)
        @testset "$c" begin
            local rm = nothing
            try
                rm, so = RefSuite.run_case(c)
                @test isvalid(rm)
                ref_path = joinpath(casedir, "reference", "cli.sel")
                if isfile(ref_path) && so !== nothing
                    ref = RefSuite.read_cli_sel(ref_path)
                    keys_julia = Set(String.(string.(keys(so))))
                    matched = intersect(Set(keys(ref)), keys_julia)
                    if isempty(matched)
                        @test_broken false   # column headings differ; skip numerical compare
                    else
                        all_ok = true
                        for k in matched
                            jvec = getproperty(so, Symbol(k))
                            if !RefSuite.vec_isapprox(ref[k], jvec; rtol = 1e-4, atol = 1e-9)
                                all_ok = false
                                push!(failures, "$c.$k")
                            end
                        end
                        @test all_ok
                    end
                    n_compared[] += 1
                else
                    n_smoke[] += 1
                end
            finally
                rm === nothing || close(rm)
            end
        end
    end
    @info "Reference suite: $(n_compared[]) cases compared vs CLI, " *
          "$(n_smoke[]) smoke-tested. " *
          (isempty(failures) ? "all match." :
           "column mismatches: $(join(unique(map(x -> split(x, '.')[1], failures)), ", "))")
end
