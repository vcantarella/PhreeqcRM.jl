# Run every example through the PHREEQC CLI to produce reference .sel files.
# Maintainer-only; the generated reference/ files ARE committed.
#
# Usage (from project root):
#   julia test/reference_suite/_scripts/regenerate_references.jl
#
# Requires `phreeqc` on PATH and at least the standard databases under
# /usr/local/share/doc/phreeqc/database/ (the macOS-Homebrew layout) or under
# deps/usr/share/doc/PhreeqcRM/database/ (the local build).

const SUITE  = joinpath(@__DIR__, "..")
const PHREEQC = let
    p = Sys.which("phreeqc")
    p === nothing && error("phreeqc CLI not on PATH")
    p
end

const DB_CANDIDATES = [
    "/usr/local/share/doc/phreeqc/database",
    joinpath(@__DIR__, "..", "..", "..", "..", "deps", "usr", "share", "doc", "PhreeqcRM", "database"),
]
function db_path(name)
    for d in DB_CANDIDATES
        p = joinpath(d, name)
        isfile(p) && return p
    end
    error("database $name not found in any of $DB_CANDIDATES")
end

# Map example name → database file. Inspected from the `#must use DATABASE`
# comments in each upstream .pqi.
function _ex15_db()
    local_copy = joinpath(@__DIR__, "ex15.dat")
    isfile(local_copy) || error("ex15.dat missing — fetch with download.sh")
    local_copy
end
const DB_FOR_CASE = Dict(
    "ex15"   => _ex15_db(),
    "ex15a"  => _ex15_db(),
    "ex15b"  => _ex15_db(),
    "ex17"   => db_path("pitzer.dat"),
    "ex17b"  => db_path("pitzer.dat"),
    "ex20a"  => db_path("iso.dat"),
    "ex20b"  => db_path("iso.dat"),
    "ex22"   => db_path("sit.dat"),
)

# Examples we cannot CLI-validate against /usr/local/bin/phreeqc:
#   - ex21: uses post-3.7 syntax not in the system phreeqc.
#   - ex12b: hits an internal stop in the v3.7 CLI; this is a known interaction.
# These cases get only a Julia smoke test (runs without erroring) and no
# numerical comparison.
const SKIP_CLI = Set(["ex21", "ex12b"])

# Per-case CLI timeout (seconds). Most run < 10s; transport runs slower.
function cli_timeout(c)
    occursin(r"^ex(11|12|13|15)", c) ? 120 : 30
end

cases = sort(filter(d -> isdir(joinpath(SUITE, d)) && d != "_scripts" && d != "_drivers",
                    readdir(SUITE)))

failures = String[]
skipped  = String[]
for c in cases
    if c in SKIP_CLI
        push!(skipped, c)
        continue
    end
    casedir = joinpath(SUITE, c)
    input = joinpath(casedir, "input.pqi")
    isfile(input) || continue
    ref_dir = joinpath(casedir, "reference")
    mkpath(ref_dir)
    out = joinpath(ref_dir, "cli.out")
    db  = get(DB_FOR_CASE, c, db_path("phreeqc.dat"))
    cd(casedir) do
        proc = nothing
        try
            proc = run(pipeline(`$PHREEQC $input $out $db`; stdout = devnull, stderr = devnull);
                       wait = false)
            t0 = time()
            while !process_exited(proc)
                if time() - t0 > cli_timeout(c)
                    kill(proc)
                    throw(ErrorException("CLI timed out after $(cli_timeout(c))s"))
                end
                sleep(0.1)
            end
            success(proc) || throw(ErrorException("CLI exit $(proc.exitcode)"))
        catch e
            push!(failures, "$c: $e")
            return
        end
        # PHREEQC writes -file from SELECTED_OUTPUT in the cwd. Collect all
        # *.sel into ref/ and pick the most-recently-written as cli.sel.
        sels = filter(f -> endswith(f, ".sel"), readdir("."))
        for f in sels
            cp(f, joinpath(ref_dir, f); force = true)
            rm(f)
        end
        for f in (basename(input) * ".out", "phreeqc.log")
            isfile(f) && rm(f)
        end
        existing = filter(f -> endswith(f, ".sel"), readdir(ref_dir))
        if !isempty(existing) && !("cli.sel" in existing)
            cp(joinpath(ref_dir, first(existing)), joinpath(ref_dir, "cli.sel"); force = true)
        end
    end
end

n_with_sel = count(c -> isfile(joinpath(SUITE, c, "reference", "cli.sel")), cases)
println()
println("Reference generation:")
println("  $n_with_sel/$(length(cases)) cases have a cli.sel for numerical comparison")
println("  skipped (CLI incompatible): $(join(skipped, ", "))")
if !isempty(failures)
    println("\n  failures ($(length(failures))):")
    foreach(f -> println("    $f"), failures)
end
