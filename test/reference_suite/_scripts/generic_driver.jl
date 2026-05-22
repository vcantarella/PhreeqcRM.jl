# Generic Julia driver for the PHREEQC reference suite.
#
# Handles any PHREEQC example whose chemistry can be expressed as cells with
# a single equilibration step:
#   - parses `input.pqi` to discover which keyword blocks (SOLUTION,
#     EQUILIBRIUM_PHASES, EXCHANGE, SURFACE, GAS_PHASE, SOLID_SOLUTIONS,
#     KINETICS) are defined with a user-number
#   - sets up `nxyz=1` cell using the lowest user-number of each block
#   - calls `run_cells!` once (or the number of steps for kinetic cases)
#   - returns the selected_output values as a NamedTuple
#
# Cases that need parameter sweeps (ex2), sequential kinetic stepping (ex9),
# or transport (ex11) have their own bespoke driver.jl files.

module GenericBatchDriver

using PhreeqcRM
using DelimitedFiles

const ROOT = realpath(joinpath(@__DIR__, "..", "..", ".."))

function database_for(case_dir::AbstractString)
    case = basename(case_dir)
    # Match the user-number choice in regenerate_references.jl.
    db_dir1 = joinpath(ROOT, "deps", "usr", "share", "doc", "PhreeqcRM", "database")
    db_dir2 = "/usr/local/share/doc/phreeqc/database"
    pick(name) = isfile(joinpath(db_dir1, name)) ? joinpath(db_dir1, name) :
                 isfile(joinpath(db_dir2, name)) ? joinpath(db_dir2, name) :
                 error("$name not found")
    case in ("ex15", "ex15a", "ex15b") &&
        return joinpath(@__DIR__, "ex15.dat")
    case in ("ex17", "ex17b")          && return pick("pitzer.dat")
    case in ("ex20a", "ex20b")         && return pick("iso.dat")
    case == "ex22"                     && return pick("sit.dat")
    return pick("phreeqc.dat")
end

"Scan a PHREEQC script for `KEYWORD <n>` declarations; return sorted user-numbers."
function _user_numbers(script::AbstractString, keyword::AbstractString)
    pat = Regex("(?mi)^\\s*$(keyword)\\s+([0-9]+)")
    nums = Int[]
    for m in eachmatch(pat, script)
        push!(nums, parse(Int, m.captures[1]))
    end
    return sort!(unique!(nums))
end

const _KEYWORDS = (
    (:solution,           "SOLUTION"),
    (:equilibrium_phases, "EQUILIBRIUM_PHASES"),
    (:exchange,           "EXCHANGE"),
    (:surface,            "SURFACE"),
    (:gas_phase,          "GAS_PHASE"),
    (:ss_assemblage,      "SOLID_SOLUTIONS"),
    (:kinetics,           "KINETICS"),
)

"""
    setup(case_dir; nxyz = 1) -> PhreeqcRMInstance

Load `case_dir/input.pqi`, configure a `nxyz`-cell PhreeqcRMInstance
according to the keyword blocks present in the script, and return it.
Caller closes.
"""
function setup(case_dir::AbstractString; nxyz::Integer = 1)
    script = read(joinpath(case_dir, "input.pqi"), String)
    rm = PhreeqcRMInstance(nxyz; nthreads = 1)
    load_database!(rm, database_for(case_dir))
    cd(case_dir) do                 # so `INCLUDE$ name` resolves
        run_string!(rm, script)
    end
    set_units!(rm; solution = SolutionUnits.MolPerL)
    set_porosity!(rm,              fill(1.0,  nxyz))
    set_saturation!(rm,            fill(1.0,  nxyz))
    set_representative_volume!(rm, fill(1.0,  nxyz))
    set_temperature!(rm,           fill(25.0, nxyz))
    set_pressure!(rm,              fill(1.0,  nxyz))
    find_components!(rm)

    # Build IC keywords from whichever blocks are defined in the script.
    kw = Dict{Symbol, Vector{Int}}()
    for (sym, kwname) in _KEYWORDS
        nums = _user_numbers(script, kwname)
        if !isempty(nums)
            kw[sym] = fill(first(nums), nxyz)
        end
    end
    set_initial_conditions!(rm; kw...)
    enable_selected_output!(rm, true)
    set_time!(rm, 0.0); set_time_step!(rm, 0.0)
    return rm
end

"""Equilibrate once. Returns the selected_output NamedTuple (or `nothing` if no SELECTED_OUTPUT)."""
function run_once(case_dir::AbstractString; nxyz::Integer = 1)
    rm = setup(case_dir; nxyz)
    try
        run_cells!(rm)
        return try
            get_selected_output(rm)
        catch
            nothing
        end
    finally
        close(rm)
    end
end

"""Parse the CLI .sel reference and return columns as a Dict{String,Vector{Float64}}.
Skips the `i_soln` row (initial solution before any reaction)."""
function read_cli_sel(path::AbstractString)
    raw = readdlm(path; header = true)
    headings = strip.(string.(raw[2][:]))
    data = raw[1]
    out = Dict{String, Vector{Float64}}()
    for (j, h) in enumerate(headings)
        col = Vector{Float64}(undef, size(data, 1))
        for i in 1:size(data, 1)
            x = data[i, j]
            col[i] = x isa AbstractString ? something(tryparse(Float64, x), NaN) :
                     Float64(x)
        end
        out[h] = col
    end
    return out, headings
end

"""Compare two values for closeness with both rtol and atol; NaN tolerant."""
function approx_eq(a::Real, b::Real; rtol = 1e-3, atol = 0.05)
    (isnan(a) && isnan(b)) && return true
    (isnan(a) || isnan(b)) && return false
    return abs(a - b) <= max(atol, rtol * max(abs(a), abs(b)))
end

end # module GenericBatchDriver
