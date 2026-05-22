# Populate `SUITE` with one entry per benchmark case.
#
# A "case" here is a small Julia driver function that builds a PhreeqcRMInstance,
# returns its state, and defines a `step!(state)` that does one transport+react
# tick. New cases are added by writing another function below — no per-case
# directory ceremony for now (the reference suite has that structure if we want
# CLI≡C≡Julia comparisons too).

const DB_CANDIDATES = [
    joinpath(@__DIR__, "..", "deps", "usr", "share", "doc", "PhreeqcRM", "database", "phreeqc.dat"),
    "/usr/local/share/doc/phreeqc/database/phreeqc.dat",
]

function _database()
    for c in DB_CANDIDATES
        isfile(c) && return c
    end
    error("no phreeqc.dat found")
end

"""
    setup_trivial_nacl(nxyz; nthreads=1)

Minimal NaCl-only chemistry, no reactants, no kinetics — pure equilibrium of
a trivial solution. Used to measure raw ccall overhead with the smallest
possible per-cell work.
"""
function setup_trivial_nacl(nxyz::Integer; nthreads::Integer = 1)
    rm = PhreeqcRMInstance(nxyz; nthreads)
    load_database!(rm, _database())
    run_string!(rm, "SOLUTION 1\n pH 7.0\n Na 1.0\n Cl 1.0 charge\nEND")
    set_units!(rm; solution = SolutionUnits.MolPerL)
    set_porosity!(rm,              fill(0.3, nxyz))
    set_saturation!(rm,            fill(1.0, nxyz))
    set_representative_volume!(rm, fill(1.0, nxyz))
    set_temperature!(rm,           fill(25.0, nxyz))
    set_pressure!(rm,              fill(1.0,  nxyz))
    find_components!(rm)
    set_initial_conditions!(rm; solution = fill(1, nxyz))
    set_time!(rm, 0.0); set_time_step!(rm, 1.0)
    c = zeros_concentrations(rm)
    get_concentrations!(rm, c)
    return (; rm, c)
end

"""
    setup_exchange_column(nxyz; nthreads=1)

Cation exchange column — the canonical PhreeqcRM transport benchmark. More
work per cell than the trivial case (one EXCHANGE reactant, one charge-
balance solve).
"""
function setup_exchange_column(nxyz::Integer; nthreads::Integer = 1)
    rm = PhreeqcRMInstance(nxyz; nthreads)
    load_database!(rm, _database())
    run_string!(rm, """
        SOLUTION 1-$(nxyz)
            units mmol/kgw
            pH 7.0
            Na 1.0
            Cl 1.0 charge
        EXCHANGE 1-$(nxyz)
            -equilibrate 1
            X 0.0011
        END
    """)
    set_units!(rm; solution = SolutionUnits.KgPerKgSolution)
    set_porosity!(rm,              fill(0.3, nxyz))
    set_saturation!(rm,            fill(1.0, nxyz))
    set_representative_volume!(rm, fill(1.0, nxyz))
    set_temperature!(rm,           fill(25.0, nxyz))
    set_pressure!(rm,              fill(1.0,  nxyz))
    find_components!(rm)
    set_initial_conditions!(rm;
        solution = collect(1:nxyz), exchange = collect(1:nxyz))
    set_time!(rm, 0.0); set_time_step!(rm, 60.0)
    c = zeros_concentrations(rm)
    get_concentrations!(rm, c)
    return (; rm, c)
end

# step! contract: takes the NamedTuple from setup_*, runs one transport+react
# tick, mutates state.c in place. Zero allocations after warmup is the bar.
function step!(state)
    set_concentrations!(state.rm, state.c)
    run_cells!(state.rm)
    get_concentrations!(state.rm, state.c)
    return nothing
end

# ── hot_loop group: per-call timings on the cation-exchange case ──
let state = setup_exchange_column(40; nthreads = 1)
    SUITE["hot_loop"]["set_concentrations__nxyz=40"] =
        @benchmarkable set_concentrations!($(state.rm), $(state.c)) samples=200 evals=1
    SUITE["hot_loop"]["run_cells__nxyz=40"] =
        @benchmarkable run_cells!($(state.rm)) samples=200 evals=1
    SUITE["hot_loop"]["get_concentrations__nxyz=40"] =
        @benchmarkable get_concentrations!($(state.rm), $(state.c)) samples=200 evals=1
    SUITE["hot_loop"]["step!__nxyz=40"] =
        @benchmarkable step!($state) samples=200 evals=1
end

let state = setup_exchange_column(1000; nthreads = 1)
    SUITE["hot_loop"]["step!__nxyz=1000"] =
        @benchmarkable step!($state) samples=50 evals=1 seconds=30
end

# ── threading group: strong scaling over the same problem ──
for n in (1, 2, 4, 8)
    n <= Sys.CPU_THREADS || continue
    state = setup_exchange_column(1000; nthreads = n)
    SUITE["threading"]["exchange1000_n=$n"] =
        @benchmarkable run_cells!($(state.rm)) samples=30 evals=1 seconds=30
end

# ── allocations group: @allocated per step (target: 0 bytes) ──
let state = setup_exchange_column(40)
    step!(state)   # warmup
    SUITE["allocations"]["step!__nxyz=40"] =
        @benchmarkable (@allocated step!($state)) samples=1 evals=1
end
let state = setup_trivial_nacl(40)
    step!(state)
    SUITE["allocations"]["trivial_step__nxyz=40"] =
        @benchmarkable (@allocated step!($state)) samples=1 evals=1
end
