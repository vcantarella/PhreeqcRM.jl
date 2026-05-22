# PhreeqcRM.jl — Julia interface to USGS PhreeqcRM

## Context

The user (computational geochemist on macOS) wants to couple **PhreeqcRM** — USGS's C++ reactive-transport reaction module — as the geochemistry step inside a Julia-side flow/transport code. The intended pattern is operator splitting: Julia transports the components, then per timestep calls `SetConcentrations` → `RunCells` → `GetConcentrations`.

The Julia ecosystem currently offers only `JPhreeqc.jl` (simulkade, unregistered, last touched Feb 2019). No `PhreeqcRM_jll` exists in Yggdrasil. PHREEQC CLI is installed on this Mac but `libphreeqcrm` is **not**.

We will build `libphreeqcrm` from source locally to start prototyping immediately, and structure the project so that swapping to a future Yggdrasil-built `PhreeqcRM_jll` is a **zero-code-change** dependency swap.

PhreeqcRM's C interface (`RM_interface_C.h`) is `extern "C"`-guarded, ~100 functions, handle-based (integer `id` per instance), returning `IRM_RESULT` codes. Array data is sized either `nxyz` (per-cell) or `nxyz*ncomps` (concentrations), **C-order** (component index varies fastest). String getters use caller-allocated buffer + length.

## What the C interface is actually doing

PhreeqcRM is a stateful C++ object with a flat C façade. Each instance holds:

- **N worker `IPhreeqc` objects** (one per OMP thread or MPI rank) — each is a self-contained PHREEQC engine with its own database tables, solution definitions, and reactant assemblages. The workers do the per-cell chemistry.
- **One `InitialPhreeqc` object** — the "scratch" engine used to parse the user's input file (`SOLUTION 1 …`, `EQUILIBRIUM_PHASES`, `EXCHANGE`, etc.). Initial and boundary conditions are pulled from here and copied into worker cells.
- **One `Utility` object** — for ad-hoc calculations (e.g. mixing).
- **Per-cell arrays** (length `nxyz`): porosity, saturation, representative volume, temperature, pressure, density, plus the per-cell mapping that says which worker-cell handles which transport cell.
- **A concentration buffer** of size `nxyz * ncomps`, sized once `FindComponents` has scanned the InitialPhreeqc instance to learn how many "components" (mass-balance elements + charge) it needs to track.

`RM_*` calls in the C interface are dispatched on an integer handle — internally an `int → PhreeqcRM*` map inside the library. The handle is stable for the instance's lifetime. All array-bearing calls follow one of two ownership patterns:

| Pattern | Who allocates | Who fills | When freed |
|---|---|---|---|
| **Caller-allocated, callee-reads** (`SetPorosity`, `SetConcentrations`, `SetTemperature`, `CreateMapping`, …) | caller (us) | library copies into its internal store | caller frees whenever; library has its own copy |
| **Caller-allocated, callee-writes** (`GetConcentrations`, `GetSolutionVolume`, `GetSelectedOutput`, `GetErrorString`, `GetComponent`, `GetSelectedOutputHeading`) | caller (us) | library writes into the buffer | caller frees |

PhreeqcRM never returns malloc'd memory the caller has to free. **Every array crossing the boundary is owned by the caller**, on both sides of the call. This is exactly the FFI pattern Julia handles best.

What `RunCells` actually does (the hot path):

1. For each cell, take the component concentrations from the buffer set by `SetConcentrations`, interpret them under the unit chosen by `SetUnitsSolution` (mg/L, mol/L, or kg/kgs), and convert to **moles in the cell** using `saturation × porosity × representative_volume`.
2. Form a PHREEQC `SOLUTION` definition from those moles for each component.
3. Couple that solution to whatever reactant blocks (`EQUILIBRIUM_PHASES`, `KINETICS`, `EXCHANGE`, `SURFACE`, `GAS_PHASE`, `SOLID_SOLUTIONS`) were associated with this cell by `InitialPhreeqc2Module`.
4. Solve the nonlinear equilibrium with Newton–Raphson; integrate any kinetic rates over `time_step` using PHREEQC's built-in ODE solver.
5. Convert the post-reaction moles back to concentrations and overwrite the corresponding slice of the internal concentration store. The user then pulls them with `GetConcentrations`.
6. If selected output is on, append one row of computed values per cell to the internal selected-output table.

Cells are independent during step 1–5, so OpenMP parallelizes the loop across `nthreads` workers.

This is why call ordering is mandatory and not just stylistic:

- `SetComponentH2O` must precede `LoadDatabase` because it changes the element set the database is parsed into.
- `LoadDatabase` must precede `RunFile` because the input file references elements/phases the database defined.
- `RunFile` must precede `FindComponents` because components are discovered by scanning the InitialPhreeqc instance.
- `FindComponents` must precede any `SetConcentrations` / `GetConcentrations` because those buffer sizes are `nxyz * ncomps` and ncomps is unknown until then.
- `SetUnitsSolution` must precede `SetConcentrations` or the numeric values are interpreted under the wrong unit and silently produce wrong moles.
- `SetTime` and `SetTimeStep` must precede `RunCells` or kinetics integrate over zero time and equilibrium happens at t=0.

We bake this into the high-level layer with assertions on the `PhreeqcRMInstance` state.

## Side-by-side: C vs Julia

The two-layer design means the **low-level** `LibPhreeqcRM` calls are 1:1 with the C calls (same names, same signatures, just `ccall`'d), while the **high-level** API hides the buffer-sizing, error-translation, and shape-validation boilerplate. Below, each block shows what the user writes in C and what they write in Julia at the high level. Where it's instructive, the **middle** column shows the low-level Julia call to make clear nothing is hidden — just wrapped.

### 1. Construct + destroy

```c
// C
int id = RM_Create(/*nxyz=*/40, /*nthreads=*/1);
if (id < 0) { fprintf(stderr, "Create failed\n"); exit(1); }
RM_SetComponentH2O(id, 0);   // 0 = false (water is not a separate component)
/* ... */
RM_Destroy(id);
```
```julia
# Julia, low level — what's generated by Clang.jl, no error translation
id = LibPhreeqcRM.RM_Create(Cint(40), Cint(1))
id < 0 && error("RM_Create failed")
LibPhreeqcRM.RM_SetComponentH2O(id, Cint(0))
# ...
LibPhreeqcRM.RM_Destroy(id)

# Julia, high level — single line, finalizer + close
rm = PhreeqcRMInstance(40; nthreads=1, component_h2o=false)   # Create + SetComponentH2O
# ...
close(rm)                                                      # Destroy, idempotent
```

**Memory**: `RM_Create` heap-allocates a C++ `PhreeqcRM` object inside the library, plus N worker IPhreeqc instances, one InitialPhreeqc, one utility (so ~3+N internal PHREEQC engines). All of this is library-owned. The Julia `PhreeqcRMInstance` struct holds just the `Cint` handle plus bookkeeping fields — no C memory references and nothing for GC to chase.

### 2. Load database + run input file

```c
// C
if (RM_LoadDatabase(id, "phreeqc.dat") != IRM_OK) { /* check error */ }
if (RM_RunFile(id, /*workers=*/1, /*initial=*/1, /*utility=*/1, "advect.pqi") != IRM_OK) { /* … */ }
```
```julia
# Julia, low level
rc = LibPhreeqcRM.RM_LoadDatabase(rm.id, "phreeqc.dat")
rc == IRM_OK || error("…")
rc = LibPhreeqcRM.RM_RunFile(rm.id, Cint(1), Cint(1), Cint(1), "advect.pqi")
rc == IRM_OK || error("…")

# Julia, high level
load_database!(rm, "phreeqc.dat")                              # throws PhreeqcRMError on rc != IRM_OK
run_file!(rm, "advect.pqi"; workers=true, initial=true, utility=true)
```

**Memory**: `RM_LoadDatabase` parses the file into the library's thermodynamic tables (`llnl.dat` ~740 KB, parsed forms larger). `RM_RunFile` populates the InitialPhreeqc instance with solution / reactant definitions parsed from the input file. All allocations live inside the library; freed by `RM_Destroy`. The string argument is converted by Julia from `String → Cstring` for the duration of the ccall — Julia keeps the temporary alive across the call via root-marking; nothing for us to manage.

### 3. Set per-cell properties (the easy arrays)

```c
// C
double porosity[40];
for (int i = 0; i < 40; i++) porosity[i] = 0.2;
RM_SetPorosity(id, porosity);    // library copies into its internal porosity store
```
```julia
# Julia, low level — pointer is passed; library reads, doesn't keep a reference
porosity = fill(0.2, 40)
LibPhreeqcRM.RM_SetPorosity(rm.id, porosity)   # ccall sig: (Cint, Ptr{Cdouble}) → IRM_RESULT

# Julia, high level
set_porosity!(rm, fill(0.2, 40))   # validates length == nxyz, throws if not
```

**Memory**: caller-allocated array of `nxyz` doubles, callee copies into its internal storage. The Julia `Vector{Float64}` may be freed by GC right after the call; the library kept its own copy. Important: **GC will not move heap-allocated Julia arrays during an in-flight `ccall`**, so passing `pointer(porosity)` is safe without any pinning. (We just have to not store the pointer across yield points outside the call.)

### 4. Discover components (the size-of-everything operation)

```c
// C
int ncomps = RM_FindComponents(id);   // scans the InitialPhreeqc instance, returns count
char heading[100];
for (int i = 0; i < ncomps; i++) {
    RM_GetComponent(id, i, heading, 100);   // caller buffer, fixed size
    printf("%d: %s\n", i, heading);
}
```
```julia
# Julia, low level
ncomps = LibPhreeqcRM.RM_FindComponents(rm.id)
names = Vector{String}(undef, ncomps)
buf = Vector{UInt8}(undef, 100)
for i in 0:ncomps-1
    LibPhreeqcRM.RM_GetComponent(rm.id, Cint(i), buf, Cint(length(buf)))
    names[i+1] = unsafe_string(pointer(buf))
end

# Julia, high level
comps = find_components!(rm)   # returns Vector{String}; caches ncomps and names in rm
@assert ncomps(rm) == length(comps)
```

**Memory**: `RM_GetComponent` writes a null-terminated string into a caller-allocated `char[100]` buffer. We allocate the buffer once and reuse it across the loop, then materialize a fresh Julia `String` per component (which copies the bytes onto the Julia heap; the `buf` can then be GC'd). Names are cached on the `PhreeqcRMInstance` so subsequent reads don't repeat the ccall loop. Buffer length 100 is safe — component names are short element symbols (`"H"`, `"O"`, `"Ca"`, `"Charge"`, `"S(6)"`).

### 5. The hot path — set / run / get concentrations

This is where layout and allocation choices dominate runtime.

**Layout convention (verified empirically against libphreeqcrm v3.9.0)**: the concentration buffer packs the **cell index fastest** and the **component index slowest**:

```
buf[i_cell + nxyz * i_comp]    // C-side: (ncomps, nxyz) row-major; one column = one cell-block per component
```

The plan's earlier draft inverted this — corrected here. The Julia shape is therefore `Matrix(nxyz, ncomps)`: each **row** is one cell, each **column** is one component across cells.

```c
// C: allocate once outside loop, reuse in place
double *c = (double*)malloc(sizeof(double) * nxyz * ncomps);
RM_GetConcentrations(id, c);                              // initial fill
for (int step = 0; step < nsteps; step++) {
    transport(c);                                         // user's transport
    RM_SetConcentrations(id, c);
    RM_SetTime(id, step * dt);
    RM_SetTimeStep(id, dt);
    RM_RunCells(id);                                      // does the chemistry
    RM_GetConcentrations(id, c);                          // overwrites c in place
}
free(c);
```

In Julia, we want exactly the same memory layout so we can pass `pointer(c)` with zero copying. Julia is column-major, so the matching shape is:

```
Matrix{Float64}(ncomps, nxyz)        # ← rows = components, columns = cells
```

A column-major `(nrows, ncols)` matrix has linear order `m[r, c] = mem[r-1 + nrows*(c-1)]`. Substituting `nrows = ncomps`, `r = i_comp+1`, `c = i_cell+1` gives `mem[i_comp + ncomps * i_cell]` — exactly PhreeqcRM's C layout. So `pointer(M)` is a valid `Ptr{Cdouble}` argument with no transpose, no copy.

```julia
# Julia, low level
c = Matrix{Float64}(undef, ncomps(rm), nxyz(rm))    # zero-copy compatible
LibPhreeqcRM.RM_GetConcentrations(rm.id, c)
for step in 1:nsteps
    transport!(c)
    LibPhreeqcRM.RM_SetConcentrations(rm.id, c)
    LibPhreeqcRM.RM_SetTime(rm.id, Cdouble(step * dt))
    LibPhreeqcRM.RM_SetTimeStep(rm.id, Cdouble(dt))
    LibPhreeqcRM.RM_RunCells(rm.id)
    LibPhreeqcRM.RM_GetConcentrations(rm.id, c)
end

# Julia, high level
c = zeros_concentrations(rm)          # constructs Matrix{Float64}(ncomps(rm), nxyz(rm))
get_concentrations!(rm, c)
for step in 1:nsteps
    transport!(c)
    set_concentrations!(rm, c)        # asserts size(c) == (ncomps(rm), nxyz(rm))
    set_time!(rm, step * dt)
    set_time_step!(rm, dt)
    run_cells!(rm)
    get_concentrations!(rm, c)        # in-place; no allocation per step
end
```

**Why the shape matters (worked example)**: 1 M cells × 30 components × 8 bytes = **240 MB per concentration matrix**. If the wrapper accepted the "natural" `(nxyz, ncomps)` shape, every `set_concentrations!` and every `get_concentrations` call would have to allocate a fresh 240 MB buffer to transpose into PhreeqcRM's order. At one transport step per second that's ~500 MB/s of garbage — the GC would dominate. With the correct `(nxyz, ncomps)` shape, zero bytes are allocated per step beyond what the user's transport code does.

The opposite shape (`Matrix(nxyz, ncomps)`) does **not** raise an error if passed through a naive wrapper — it would silently scramble concentrations across cells. The high-level layer prevents this by:
- Forcing construction via `zeros_concentrations(rm)`, which returns the correct shape.
- `set_concentrations!` and `get_concentrations!` assert `size(c) == (ncomps(rm), nxyz(rm))` before the ccall.
- Documentation states the shape contract loudly.

A `bycell(c)` helper returns `eachcol(c)` for ergonomic per-cell iteration without copies. Users wanting to look at "all values of component i across cells" use `c[i, :]` which is a copy (a row of a column-major matrix) — acceptable for inspection but not for the hot path.

### 6. Selected output (the same C-order trick, again)

```c
// C
RM_SetSelectedOutputOn(id, 1);
// ... after RunCells ...
int ncols = RM_GetSelectedOutputColumnCount(id);
int nrows = RM_GetSelectedOutputRowCount(id);     // == nxyz when selected output is per cell
double *so = (double*)malloc(sizeof(double) * nrows * ncols);
RM_GetSelectedOutput(id, so);                     // so[i_row * ncols + i_col]
char head[100];
for (int j = 0; j < ncols; j++) {
    RM_GetSelectedOutputHeading(id, j, head, 100);
    /* … */
}
free(so);
```
```julia
# Julia, high level
enable_selected_output!(rm, true)
# ...after run_cells!(rm)...
out = get_selected_output(rm)        # NamedTuple{(:pH, :pe, :C, ...)}(Vector{Float64}...)
@show out.pH                          # length == nxyz
```

Internally, the high-level `get_selected_output` allocates a `Matrix{Float64}(ncols, nrows)` (column-major Julia matching the C row-major layout the same way as concentrations), calls `RM_GetSelectedOutput`, then slices each column into the NamedTuple. Headings are queried once on first call and cached. For large problems where the per-cell selected-output snapshot is heavy (e.g. 1 M cells × 100 columns ≈ 800 MB), we also expose an in-place form `get_selected_output!(rm, buf)` and document that users should snapshot to disk periodically rather than retaining every step.

### 7. Errors

```c
// C
IRM_RESULT rc = RM_RunFile(id, 1, 1, 1, "broken.pqi");
if (rc != IRM_OK) {
    int len = RM_GetErrorStringLength(id);
    char *buf = (char*)malloc(len + 1);
    RM_GetErrorString(id, buf, len + 1);
    fprintf(stderr, "PhreeqcRM error: %s\n", buf);
    free(buf);
    exit(1);
}
```
```julia
# Julia, high level — caller writes none of this; the wrapper does:
function check_result(rc::Cint, rm::PhreeqcRMInstance)
    rc == Cint(IRM_OK) && return
    len = LibPhreeqcRM.RM_GetErrorStringLength(rm.id)
    buf = Vector{UInt8}(undef, len + 1)
    LibPhreeqcRM.RM_GetErrorString(rm.id, buf, Cint(length(buf)))
    throw(PhreeqcRMError(IRMResult(rc), unsafe_string(pointer(buf))))
end

# User just writes:
run_file!(rm, "broken.pqi")   # throws ::PhreeqcRMError with .code and .message
```

## Memory considerations — full ledger

| Allocation | Size | Who allocates | Who frees | When |
|---|---|---|---|---|
| C++ `PhreeqcRM` object + N IPhreeqc workers + InitialPhreeqc + utility | varies; ~MBs depending on database | library (heap) | library, on `RM_Destroy` | once per instance |
| Database tables (parsed thermodynamic data) | 100s of KB to few MB | library | library, on `RM_Destroy` | once, on `LoadDatabase` |
| Per-cell property stores (porosity, sat, T, P, rv, density) | `nxyz × 8 B` each | library | library | once per `SetXxx` call (overwritten in place) |
| Library's internal concentration store | `nxyz × ncomps × 8 B` | library | library | sized on `FindComponents`, overwritten in place |
| **User concentration matrix** (Julia) | `nxyz × ncomps × 8 B` | **user, once** | Julia GC | **outside hot loop**; reuse in place via `set_concentrations!` / `get_concentrations!` |
| User per-cell property vectors | `nxyz × 8 B` | user | Julia GC | once at setup; reusable |
| String getter scratch buffer | ~100 B (component names) or `RM_GetErrorStringLength` (errors) | wrapper (Julia heap) | Julia GC | per-call, throwaway |
| Component names cache | `ncomps × small` | wrapper | Julia GC, on `close(rm)` | once, on `find_components!` |
| Selected-output matrix | `ncols × nrows × 8 B` | wrapper | Julia GC | per `get_selected_output` call unless using in-place form |
| Initial conditions array | `nxyz × 7 × 4 B` (Cint) | user | Julia GC | one-shot at setup |

**Things to be paranoid about**:

1. **Allocating inside the time loop.** The user's concentration matrix MUST be allocated once and reused. The wrapper's `get_concentrations!(rm, c)` is in-place; `get_concentrations(rm)` (no bang) allocates and should be marked "not for hot paths" in docstrings.

2. **Concentration matrix shape.** `(nxyz, ncomps)` not `(nxyz, ncomps)`. Wrong shape silently scrambles all data across cells without raising an error. The wrapper enforces shape on every `set_concentrations!` / `get_concentrations!`. The constructor `zeros_concentrations(rm)` is the recommended way to build the matrix so users don't get this wrong.

3. **Non-contiguous views.** `view(c, :, 2:end-1)` of a `Matrix(ncomps, nxyz)` IS contiguous (column ranges of a column-major matrix), but `view(c, 1:5, :)` is not. The wrapper accepts `DenseMatrix{Float64}` and uses `Base.unsafe_convert(Ptr{Cdouble}, c)` so contiguous views work transparently. Non-contiguous slices passed in would silently corrupt the call — we reject anything that isn't `Matrix` or a contiguous `StridedMatrix`, with a clear error message.

4. **Finalizer races.** The finalizer for `PhreeqcRMInstance` is a safety net only; it calls `close(rm)` if not already closed. `Base.close` sets a `destroyed` flag before calling `RM_Destroy`, and the finalizer checks the flag — so a user who called `close(rm)` explicitly will not see a double-free even if the GC eventually fires the finalizer too. Critically, the finalizer must **not** be the primary path: `RM_Destroy` joins on internal OpenMP threads, and triggering that from arbitrary GC contexts (especially during a `ccall` that is somehow already on the same instance, which only happens if a user holds two references) is asking for trouble. The do-block helper `with_instance(...) do rm ... end` and explicit `close` are the documented patterns.

5. **String lifetime in `ccall`.** Passing `"path/to/file"` directly to a `ccall(..., Cstring, ...)` is safe — Julia roots the temporary `Cstring` for the duration of the call. No need for `Base.cconvert` gymnastics.

6. **Pointer alignment.** `Cdouble` is 8-byte aligned; Julia `Vector{Float64}` / `Matrix{Float64}` storage is at least 8-byte aligned. No issue.

7. **MPI workers + callbacks.** `RM_SetMpiWorkerCallback` takes a C function pointer. Out of scope for v1 — we will not expose this and will leave MPI off in the build. Documented as a known limitation.

8. **OpenMP × Julia threads.** PhreeqcRM's OpenMP, if both are at default thread count, will spawn `nthreads_omp × nthreads_julia` workers contending for cores. We default the constructor's `nthreads=1` and call `RM_SetThreadCount` explicitly so users opt into parallelism with eyes open.

## Architecture decision: split into two packages

Two co-developed packages in this workspace, mirroring the eventual Yggdrasil layout:

| Package | Role | When real JLL lands |
|---|---|---|
| `PhreeqcRM_jll` (local stub) | Mimics Yggdrasil JLL: exposes `const libphreeqcrm::String` resolved from `ENV["JULIA_PHREEQCRM_PATH"]`. ~30 lines, no logic. | Delete the local stub; `Pkg.add PhreeqcRM_jll` from General. `PhreeqcRM.jl` source is unchanged. |
| `PhreeqcRM.jl` | The actual wrapper. Two-layer: Clang.jl-generated `LibPhreeqcRM` submodule + idiomatic high-level API. Depends on `PhreeqcRM_jll`. | No change. |

Single project with env-var lookup also works but every user grows dependent on the env var, and switching to a real JLL becomes a user-facing breaking change. The split costs one extra `Project.toml` and a stub module; the migration is then a pure dependency swap.

## PHREEQC script vs PhreeqcRM API — where chemistry lives

A common source of confusion: PhreeqcRM does **not** replace PHREEQC's input language. The chemistry — what minerals can precipitate, what exchange sites exist, what surface complexation reactions are active, what kinetic rate laws govern dissolution — is **still defined in a PHREEQC input script** using the same keyword blocks that the standalone `phreeqc` CLI consumes. PhreeqcRM's job is to consume that script once into the InitialPhreeqc instance, then drive the per-cell chemistry calculations from a transport simulator.

The Julia API does **not** expose `SOLUTION` / `EXCHANGE` / `EQUILIBRIUM_PHASES` etc. as Julia structs. Doing so would mean reimplementing PHREEQC's parser, which is large, evolving, and out of scope. Users hand PhreeqcRM a `.pqi` file (or a string), and the Julia side controls *which* numbered solution / exchange / etc. lives in *which* cell.

### Where each concept is defined

| Concept | Defined where | How the Julia API references it |
|---|---|---|
| Elements, species, log K, Debye–Hückel coefficients | **Database file** (`phreeqc.dat`, `llnl.dat`, `sit.dat`, …) | `load_database!(rm, path)` |
| Numbered **SOLUTION** compositions (initial & boundary waters) | PHREEQC input script: `SOLUTION 1 …`, `SOLUTION 0 …` | `run_file!(rm, "input.pqi")` → solutions live in InitialPhreeqc; assign per cell with `set_initial_conditions!(rm; solution = …)` |
| **EQUILIBRIUM_PHASES** (mineral assemblages, target SI, initial moles) | Script: `EQUILIBRIUM_PHASES 1 …` | `set_initial_conditions!(rm; equilibrium_phases = …)` |
| **EXCHANGE** (cation exchange capacity + initial occupancy) | Script: `EXCHANGE 1 …` | `set_initial_conditions!(rm; exchange = …)` |
| **SURFACE** (surface complexation sites + electrostatic model) | Script: `SURFACE 1 …` | `set_initial_conditions!(rm; surface = …)` |
| **GAS_PHASE**, **SOLID_SOLUTIONS** | Script: `GAS_PHASE 1 …`, `SOLID_SOLUTIONS 1 …` | `set_initial_conditions!(rm; gas_phase = …, ss_assemblage = …)` |
| **KINETICS** assignments + **RATES** (rate-law Basic code) | Script: `KINETICS 1 …` and `RATES …` | `set_initial_conditions!(rm; kinetics = …)`; the Basic rate code runs inside PhreeqcRM during `run_cells!` |
| Which output columns to retrieve | Script: `SELECTED_OUTPUT 1 …` (or `USER_PUNCH`) | `enable_selected_output!(rm, true)` + `get_selected_output(rm)` after `run_cells!` |
| **Number of cells** (`nxyz`) | Julia constructor | `PhreeqcRMInstance(nxyz; …)` |
| **Cell mapping** (transport-cell → reaction-cell) | Julia | `set_mapping!(rm, grid2chem)` |
| Per-cell **porosity, saturation, T, P, density, rep. volume** | Julia (per timestep if you want) | `set_porosity!`, `set_saturation!`, … |
| **Component concentrations per cell** | Julia (every transport step) | `set_concentrations!(rm, c)` / `get_concentrations!(rm, c)` |
| **Time** and **time step** | Julia | `set_time!`, `set_time_step!` |

### Worked example — an `EXCHANGE` column transport problem

The PHREEQC script (`exchange_column.pqi`) defines the chemistry, written in PHREEQC's own keyword language:

```
TITLE Chloride/sodium transport with cation exchange
DATABASE phreeqc.dat

SOLUTION 0   Inflow water (high Ca, low Na)
    units            mmol/kgw
    pH               7.0
    Ca               1.0
    Cl               2.0  charge

SOLUTION 1   Initial column water (Na-saturated)
    units            mmol/kgw
    pH               7.0
    Na               1.0
    Cl               1.0  charge

EXCHANGE 1   Initial column exchanger
    -equilibrate     1            # equilibrate with SOLUTION 1
    X                0.0011       # CEC in mol of sites per kg water

SELECTED_OUTPUT 1
    -reset           false
    -ph              true
    -totals          Ca Na Cl

END
```

The PhreeqcRM-using Julia code (`couple.jl`):

```julia
using PhreeqcRM

nxyz = 40
rm = PhreeqcRMInstance(nxyz; nthreads = 1)

# 1. Chemistry definitions: database + script.
load_database!(rm, "/usr/local/share/doc/phreeqc/database/phreeqc.dat")
run_file!(rm, "exchange_column.pqi")      # populates InitialPhreeqc with SOLUTION 0, 1, EXCHANGE 1

# 2. Unit conventions (must match the script's unit choice).
set_units!(rm; solution = SolutionUnits.MolPerL,
                exchange  = ExchangeUnits.MolPerL)

# 3. Cell properties — Julia owns these, not the script.
set_porosity!(rm,              fill(0.3, nxyz))
set_saturation!(rm,            fill(1.0, nxyz))
set_representative_volume!(rm, fill(1.0, nxyz))   # liters
set_temperature!(rm,           fill(25.0, nxyz))
set_pressure!(rm,              fill(1.0, nxyz))

# 4. Component discovery.
comps = find_components!(rm)              # e.g. ["H", "O", "Charge", "Ca", "Cl", "Na"]

# 5. Initial conditions: every cell uses SOLUTION 1 from the script, plus EXCHANGE 1.
set_initial_conditions!(rm;
    solution = fill(1, nxyz),             # SOLUTION 1 in every cell
    exchange = fill(1, nxyz),             # EXCHANGE 1 in every cell
)                                          # everything else (EQ phases, surfaces, etc.) defaults to -1 = none

# 6. Boundary condition: inflow water = SOLUTION 0, converted to component-concentration form.
bc = initial_phreeqc_to_concentrations(rm; solution = [0])   # Matrix(ncomps, 1)

# 7. Allocate the per-cell concentration matrix once.
c = zeros_concentrations(rm)              # Matrix{Float64}(ncomps(rm), nxyz)
get_concentrations!(rm, c)                # fill from initial cells

# 8. Time loop — Julia-side transport + PhreeqcRM reaction step.
enable_selected_output!(rm, true)
dt = 1.0  # seconds
for step in 1:300
    upwind_advection!(c, bc; cfl = 0.9)   # user-defined; modifies c in place
    set_concentrations!(rm, c)
    set_time!(rm, step * dt)
    set_time_step!(rm, dt)
    run_cells!(rm)
    get_concentrations!(rm, c)
end

# 9. Pull what SELECTED_OUTPUT requested.
out = get_selected_output(rm)             # NamedTuple{(:pH, :Ca, :Na, :Cl)}
close(rm)
```

The Julia code never names "calcite" or "cation exchange Gaines-Thomas" — those are entirely the script's concern. The Julia code controls geometry, time, transport, and result extraction.

### When to use `run_string!` vs `run_file!`

`run_file!` is for scripts shipped alongside Julia code. `run_string!(rm, """SOLUTION 1 …""")` is convenient when:
- The script is generated programmatically (e.g. parameter sweeps).
- Tests need to define inline chemistry without writing temp files.

Both populate the same InitialPhreeqc instance; the user can call them multiple times to accumulate definitions before `find_components!`.

## Repository layout

```
/Users/vcantarella/wc/phreeqc_in_julia/
├── PhreeqcRM_jll/                       # local stub package (Pkg.dev'd from PhreeqcRM)
│   ├── Project.toml                     # name="PhreeqcRM_jll", deps: Libdl
│   └── src/PhreeqcRM_jll.jl             # exports const libphreeqcrm
├── PhreeqcRM/                           # user-facing wrapper
│   ├── Project.toml                     # deps: PhreeqcRM_jll, Libdl. Weakdeps: DataFrames
│   ├── README.md
│   ├── gen/
│   │   ├── Project.toml                 # pins Clang.jl
│   │   ├── generator.jl
│   │   ├── generator.toml
│   │   └── include/RM_interface_C.h     # vendored at a pinned upstream tag
│   ├── src/
│   │   ├── PhreeqcRM.jl                 # top-level module
│   │   ├── LibPhreeqcRM.jl              # GENERATED — do not hand-edit
│   │   ├── errors.jl
│   │   ├── units.jl
│   │   ├── instance.jl
│   │   ├── components.jl
│   │   ├── concentrations.jl
│   │   ├── selected_output.jl
│   │   └── transport.jl                 # do-block helper, lifecycle utilities
│   ├── ext/
│   │   └── PhreeqcRMDataFramesExt.jl    # selected output → DataFrame
│   ├── examples/
│   │   └── advection_reaction.jl
│   └── test/
│       └── runtests.jl
└── deps/                                # local build of libphreeqcrm (gitignored)
    ├── build_phreeqcrm.sh
    ├── README.md
    ├── src/                             # cloned phreeqcrm source
    ├── build/                           # cmake build dir
    └── usr/lib/libphreeqcrm.dylib
```

`PhreeqcRM_jll/src/PhreeqcRM_jll.jl` (entire content):
```julia
module PhreeqcRM_jll
using Libdl
const libphreeqcrm = let
    p = get(ENV, "JULIA_PHREEQCRM_PATH", "")
    !isempty(p) ? p :
        error("Set JULIA_PHREEQCRM_PATH to libphreeqcrm.dylib path; see deps/README.md")
end
const PATH = dirname(libphreeqcrm)
const LIBPATH = PATH
export libphreeqcrm
end
```
This mirrors the public surface (`libphreeqcrm`, `PATH`, `LIBPATH`) of a real JLLWrappers-generated package well enough for the wrapper not to care which one is loaded.

## Julia user interface (target API)

End-to-end example mirroring the 1D advection-reaction case from the paper:

```julia
using PhreeqcRM

# 1. Construct — calls RM_Create + RM_SetComponentH2O. No file I/O.
rm = PhreeqcRMInstance(40;            # nxyz cells
                       nthreads = 1,  # default 1 to avoid OMP×Julia oversubscription
                       component_h2o = false)

# 2. Load database and read PHREEQC input (defines initial/boundary solutions).
load_database!(rm, "/usr/local/share/doc/phreeqc/database/phreeqc.dat")
run_file!(rm, "advect.pqi"; workers=true, initial=true, utility=true)

# 3. Cell-to-chemistry mapping (optional; default identity).
set_mapping!(rm, collect(0:39))   # one-to-one

# 4. Units — `solution` is required, the others optional but recommended.
set_units!(rm;
    solution      = SolutionUnits.MgPerL,
    pp_assemblage = PPAssemblageUnits.MolPerL,
    exchange      = ExchangeUnits.MolPerL,
    surface       = SurfaceUnits.MolPerL,
    gas_phase     = GasPhaseUnits.MolPerL,
    ss_assemblage = SSAssemblageUnits.MolPerL,
    kinetics      = KineticsUnits.MolPerL,
)

# 5. Per-cell physical properties (Vector{Float64}, length == nxyz).
set_porosity!(rm,              fill(0.2, 40))
set_saturation!(rm,            fill(1.0, 40))
set_representative_volume!(rm, fill(1.0, 40))    # liters
set_temperature!(rm,           fill(25.0, 40))
set_pressure!(rm,              fill(1.0,  40))

# 6. Discover components — required before any concentration call.
comps = find_components!(rm)             # returns Vector{String}, also cached in rm
@assert ncomps(rm) == length(comps)

# 7. Initial conditions: solution 1 in every cell.
set_initial_conditions!(rm, fill(1, 40))

# 8. Boundary concentrations: pull from solution 0 in the InitialPhreeqc instance.
bc = initial_phreeqc_to_concentrations(rm, [0])   # Matrix{Float64}(ncomps, 1)

# 9. Concentration matrix in PhreeqcRM's expected C-order layout.
#    NOTE: shape is (ncomps, nxyz), NOT (nxyz, ncomps).
#    With column-major Julia this gives zero-copy vec(c) → component-fastest C-order.
c = zeros_concentrations(rm)             # Matrix{Float64}(undef, ncomps(rm), nxyz(rm))
get_concentrations!(rm, c)

# 10. Time stepping loop.
set_time!(rm, 0.0)
set_time_step!(rm, 86400.0)              # 1 day in seconds (PHREEQC default unit)

for step in 1:120
    upwind_transport!(c, bc; cfl=0.9)    # user-defined Julia transport
    set_concentrations!(rm, c)
    run_cells!(rm)
    get_concentrations!(rm, c)
    set_time!(rm, step * 86400.0)
end

# 11. Selected output (after enabling and running cells at least once).
enable_selected_output!(rm, true)
run_cells!(rm)
out = get_selected_output(rm)            # NamedTuple{names}(Tuple{Vector{Float64},...})
@show out.pH

# 12. Teardown — primary path. Finalizer is only a safety net.
close(rm)
```

Do-block lifecycle helper:
```julia
PhreeqcRM.with_instance(40; nthreads=1) do rm
    load_database!(rm, "phreeqc.dat")
    # ...
end   # RM_Destroy called even on exception
```

### Function reference (committed surface)

```julia
# Construction & lifecycle
PhreeqcRMInstance(nxyz::Integer; nthreads::Integer=1, component_h2o::Bool=false)
Base.close(rm::PhreeqcRMInstance)
isvalid(rm::PhreeqcRMInstance)::Bool
with_instance(f, nxyz; kwargs...)

# Optional file output (off by default)
open_output!(rm; prefix::AbstractString, dir::AbstractString=pwd())
close_output!(rm)

# Database & PHREEQC input
load_database!(rm, path::AbstractString)
run_file!(rm, path::AbstractString; workers=true, initial=true, utility=true)
run_string!(rm, input::AbstractString; workers=true, initial=true, utility=true)

# Cell mapping
set_mapping!(rm, grid2chem::AbstractVector{<:Integer})

# Units — solution kwarg required, others default to PhreeqcRM defaults
set_units!(rm; solution::SolutionUnits.T,
                pp_assemblage::PPAssemblageUnits.T = PPAssemblageUnits.MolPerL,
                exchange::ExchangeUnits.T          = ExchangeUnits.MolPerL,
                surface::SurfaceUnits.T            = SurfaceUnits.MolPerL,
                gas_phase::GasPhaseUnits.T         = GasPhaseUnits.MolPerL,
                ss_assemblage::SSAssemblageUnits.T = SSAssemblageUnits.MolPerL,
                kinetics::KineticsUnits.T          = KineticsUnits.MolPerL)

# Per-cell setters (Vector{Float64}, length == nxyz)
set_porosity!(rm, p)
set_saturation!(rm, s)
set_representative_volume!(rm, v)
set_temperature!(rm, T)
set_pressure!(rm, P)
set_density!(rm, ρ)

# Components — must be called once after database+run_file
find_components!(rm)::Vector{String}
ncomps(rm)::Int
nxyz(rm)::Int
components(rm)::Vector{String}

# Initial conditions
set_initial_conditions!(rm, ic::AbstractVector{<:Integer})           # 1 solution-id per cell
initial_phreeqc_to_concentrations(rm, ic::AbstractVector{<:Integer}) # for boundary cells

# Concentration I/O — Matrix shape is (ncomps, nxyz)
zeros_concentrations(rm)::Matrix{Float64}
get_concentrations!(rm, c::AbstractMatrix{Float64})
get_concentrations(rm)::Matrix{Float64}
set_concentrations!(rm, c::AbstractMatrix{Float64})

# Time stepping
set_time!(rm, t::Real)
set_time_step!(rm, Δt::Real)
run_cells!(rm)

# Computed properties (per cell)
get_solution_volume(rm)::Vector{Float64}
get_density(rm)::Vector{Float64}
get_saturation(rm)::Vector{Float64}

# Selected output
enable_selected_output!(rm, on::Bool)
get_selected_output(rm)::NamedTuple   # column-name => Vector{Float64}
selected_output_headings(rm)::Vector{String}

# Errors
struct PhreeqcRMError <: Exception
    code::IRMResult
    message::String
end
```

Returned matrix from `get_concentrations` is `Matrix{Float64}(ncomps(rm), nxyz(rm))`. Each **column** is one cell. This is opposite to the naive `(nxyz, ncomps)` shape but is necessary so that `vec(c)` is a zero-copy view of PhreeqcRM's component-fastest C layout. A `bycell(c)` helper returns `eachcol(c)` for ergonomic per-cell iteration without copies.

## Threading model — combining Julia threads with PhreeqcRM OpenMP

PhreeqcRM parallelizes the `RunCells` loop with OpenMP — each OMP thread runs reactions on its own subset of cells using a dedicated worker `IPhreeqc`. The user can also have Julia threads (`Threads.nthreads()`) doing transport, I/O, or domain decomposition. The two thread pools are **completely independent**, and combining them naively gives `nthreads_julia × nthreads_omp` workers contending for cores.

Three useful patterns. We support all three and the test suite covers each.

### Pattern A — Single instance, OMP-only for reactions (default & recommended)

```julia
rm = PhreeqcRMInstance(nxyz; nthreads = Threads.nthreads())   # all cores → OMP
# Julia main task does transport serially (or with @simd / vectorized broadcasts)
for step in 1:nsteps
    transport!(c)
    set_concentrations!(rm, c)
    set_time!(rm, step*dt); set_time_step!(rm, dt)
    run_cells!(rm)             # uses all OMP threads internally
    get_concentrations!(rm, c)
end
```

Best for reaction-dominated problems (lots of kinetics, many minerals, complex surfaces). Simple, no domain decomposition. No oversubscription because Julia transport doesn't spawn threads.

### Pattern B — Domain decomposition, multiple PhreeqcRM instances, Julia threads only

```julia
nchunks = Threads.nthreads()
chunk_ranges = collect(Iterators.partition(1:nxyz, cld(nxyz, nchunks)))
rms = [PhreeqcRMInstance(length(r); nthreads = 1) for r in chunk_ranges]  # OMP off
# ... initial setup per rm ...
cs = [zeros_concentrations(rms[i]) for i in eachindex(rms)]

for step in 1:nsteps
    transport_with_halo_exchange!(cs, chunk_ranges)   # user-written; threads as appropriate
    Threads.@threads for i in eachindex(rms)
        set_concentrations!(rms[i], cs[i])
        set_time!(rms[i], step*dt); set_time_step!(rms[i], dt)
        run_cells!(rms[i])
        get_concentrations!(rms[i], cs[i])
    end
end
```

Best for transport-dominated or memory-bound problems where Julia transport benefits from threading. Chunk boundaries require halo-exchange logic the user writes (transport's concern, not the reaction step's). Set `nthreads=1` per instance to avoid `K × M` oversubscription.

### Pattern C — Single instance OMP + Julia threads for orthogonal work

```julia
rm = PhreeqcRMInstance(nxyz; nthreads = max(1, Threads.nthreads() - 1))   # leave one core for Julia
output_channel = Channel{NamedTuple}(8)

# Background Julia task writes selected output to disk in parallel with the next step
writer_task = Threads.@spawn for snap in output_channel
    save_to_disk(snap)
end

for step in 1:nsteps
    transport!(c)
    set_concentrations!(rm, c)
    set_time!(rm, step*dt); set_time_step!(rm, dt)
    run_cells!(rm)
    get_concentrations!(rm, c)
    put!(output_channel, get_selected_output(rm))   # background writer drains
end
close(output_channel); wait(writer_task)
```

Useful in production runs where I/O or post-processing would otherwise serialize behind reactions. Reserve one Julia thread for the spawned task; let OMP take the rest.

### Thread-safety contract

- **Within a single instance**: only one `RM_*` call at a time. The library's OMP internals already parallelize the reaction loop; calling two `RM_*` operations on the same instance from two Julia threads concurrently is undefined behavior.
- **Across instances**: two `PhreeqcRMInstance` objects can be driven from two Julia threads concurrently. The library's internal `int → PhreeqcRM*` registry is read-only after `RM_Create` returns. **However** — this is upstream-undocumented; we will treat it as supported only after the multi-instance threading test passes.
- The wrapper does **not** add a per-instance lock — that would be invisible overhead the single-threaded user pays for nothing. It is the user's responsibility (per the contract above) not to drive one instance from multiple threads.

### Defaults

- Constructor default: `nthreads = 1`. Users opt in to OMP threading explicitly. Avoids accidental oversubscription when `Threads.nthreads()` is high and the user's transport already threads.
- We always call `RM_SetThreadCount(id, n)` in the constructor (not just pass `n` to `RM_Create`) so the value is authoritative even if the library would otherwise honor `OMP_NUM_THREADS`.
- The wrapper exposes `thread_count(rm)` (returns the OMP count actually configured) and warns at construction if `Threads.nthreads() * nthreads > Sys.CPU_THREADS`.

## Validation methodology — three-way pipeline

Bugs in a Julia binding can hide in three places: (a) the upstream C++ library itself (rare; PhreeqcRM is mature), (b) the C compilation / linking / FFI surface we expose, (c) our Julia high-level wrapper. A single Julia-vs-reference comparison can't tell us *which* layer broke. To localize bugs cleanly we run **every test case through three independent execution paths** and compare them pairwise:

1. **PHREEQC CLI** — run the unmodified `.pqi` script with `/usr/local/bin/phreeqc input.pqi`. Output is the **chemistry reference**: this is what the standalone PHREEQC engine says the right answer is.
2. **C driver against `libphreeqcrm`** — a hand-written C program that uses the same `.pqi` script via `RM_RunFile` and reproduces the same scenario through PhreeqcRM. Its `SELECTED_OUTPUT` is compared to (1). **If (2) matches (1)**: the build, the linking, the library, and the C surface all work correctly. If they don't match, the bug is upstream-of-Julia.
3. **Julia driver using `PhreeqcRM.jl`** — the same scenario expressed through our high-level Julia API. Its output is compared to (2). **If (3) matches (2)**: our Julia wrapper is correct. We also measure the per-step wall-clock and allocation overhead of (3) vs (2) — this is the wrapper's tax.

Each test case is a directory under `PhreeqcRM/test/reference_suite/<case-name>/` containing exactly:

```
input.pqi              # PHREEQC input (the chemistry definition; same across all three drivers)
driver.c               # C driver using libphreeqcrm
driver.jl              # Julia driver using PhreeqcRM
README.md              # what this case exercises (1 paragraph)
reference/             # committed golden outputs (regenerated only on intentional update)
  phreeqc_cli.sel      # output of `phreeqc input.pqi`
  c_driver.sel         # output of compiled driver.c, must equal phreeqc_cli.sel
```

### Numerical comparison rule

PHREEQC's `SELECTED_OUTPUT` is a tab-separated table of doubles. We compare element-wise with **`rtol = 1e-8, atol = 1e-12`** for all three pairs (CLI vs C, CLI vs Julia, C vs Julia). The tolerance is tight enough to catch real arithmetic divergence (e.g. wrong unit conversion, swapped components) but loose enough to absorb the last-bit difference between repeated OpenMP runs on the same hardware. Shipped reference files are produced **once** with `nthreads = 1` to be deterministic.

### Cases to cover (the suite)

We import every PHREEQC textbook example that is meaningful in a transport-coupling context, plus the upstream PhreeqcRM-specific test cases. Initial sweep:

| Case dir | Chemistry exercised | Source |
|---|---|---|
| `ex01_speciation` | Aqueous speciation only | PHREEQC manual Ex 1 |
| `ex02_equilibrium_phases` | Mineral equilibria with PP assemblage | Ex 2 |
| `ex03_mixing` | Solution mixing via Utility instance | Ex 3 |
| `ex04_titration` | Reactant titration | Ex 4 |
| `ex05_irreversible` | Irreversible reactions | Ex 5 |
| `ex06_reaction_path` | Path simulation | Ex 6 |
| `ex07_gas_phase` | Gas-phase equilibria | Ex 7 |
| `ex08_exchange` | Cation exchange | Ex 8 |
| `ex09_kinetics` | Kinetic reactant + RATES Basic | Ex 9 |
| `ex10_solid_solutions` | SOLID_SOLUTIONS block | Ex 10 |
| `ex11_transport_exchange` | 1D advection + cation exchange (the canonical PhreeqcRM case) | Ex 11 |
| `ex12_kinetic_transport` | 1D advection + kinetics | Ex 12 |
| `ex13_biodegradation` | Multi-component kinetic transport | Ex 13 |
| `ex14_surface_complex` | Surface complexation, double layer | Ex 14 |
| `ex15_kinetic_oxidation` | 1D advection + redox kinetics | Ex 15 |
| `ex17_isotopes` | Isotope tracking | Ex 17 |
| `ex19_gas_exchange` | Open-system gas exchange | Ex 19 |
| `ex22_pitzer` | High-ionic-strength Pitzer model (uses `pitzer.dat`) | Ex 22 |
| `advect_simple` | The canonical PhreeqcRM advect.pqi from the distribution | PhreeqcRM Tests/ |
| `momas_easy_1d` | MoMaS reactive transport benchmark, easy 1D | PhreeqcRM Tests/ |
| `momas_medium_1d` | MoMaS medium 1D | PhreeqcRM Tests/ |

(Cases 16, 18, 20, 21 from the PHREEQC manual exercise inverse modeling / batch-only features and are skipped — PhreeqcRM is not a fit for those.)

Adding a new case is mechanical: create the directory, drop in `input.pqi`, write `driver.c` and `driver.jl`, run the generator below to populate `reference/`. The harness automatically picks it up.

### Reference generation (maintainer one-time, then committed)

`PhreeqcRM/test/reference_suite/regenerate.jl`:
```julia
# Run from project root with phreeqc on PATH.
using PhreeqcRM
for case in readdir("PhreeqcRM/test/reference_suite"; join = true)
    isdir(case) || continue
    cd(case) do
        # (1) Run PHREEQC CLI.
        run(`phreeqc input.pqi reference/phreeqc_cli.out reference/phreeqc_cli.sel`)
        # (2) Build and run C driver.
        run(`make -C $(joinpath(@__DIR__, ".."))/c_build $(basename(case))`)
        run(`./$(basename(case))_driver`)
        cp("c_driver.sel", "reference/c_driver.sel"; force = true)
        # Sanity: CLI vs C must already match before we commit references.
        @assert isapprox(readdlm("reference/phreeqc_cli.sel"),
                         readdlm("reference/c_driver.sel");
                         rtol = 1e-8, atol = 1e-12)
    end
end
```
Reference files are committed. The CI then re-verifies CLI ≡ C ≡ Julia on every run; if upstream PhreeqcRM bumps and changes a number, the CLI≡C comparison breaks first and we know to refresh references intentionally rather than silently absorbing a regression.

### C-driver build system

`PhreeqcRM/test/c_build/Makefile`:
```makefile
LIB     := ../../../deps/usr/lib/libphreeqcrm.dylib
INCDIR  := ../../../deps/usr/include
CFLAGS  := -I$(INCDIR) -O2 -std=c99 -Wall -Wextra
LDFLAGS := -L$(dir $(LIB)) -lphreeqcrm -Wl,-rpath,$(dir $(LIB))

CASES   := $(notdir $(wildcard ../reference_suite/*))
DRIVERS := $(addsuffix _driver, $(CASES))

all: $(DRIVERS)

%_driver: ../reference_suite/%/driver.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)
```
One `make` builds every C driver; CI invokes it once before running the validation harness.

### The harness (a TestItem)

`PhreeqcRM/test/test_reference_suite.jl`:
```julia
@testitem "Reference suite: CLI ≡ C ≡ Julia" tags=[:integration] setup=[Fixtures] begin
    using DelimitedFiles
    suite_dir = joinpath(@__DIR__, "reference_suite")
    cases = filter(p -> isdir(joinpath(suite_dir, p)), readdir(suite_dir))
    @assert !isempty(cases)
    for case in cases
        @testset "$case" begin
            casedir = joinpath(suite_dir, case)
            ref_cli = readdlm(joinpath(casedir, "reference/phreeqc_cli.sel"))
            ref_c   = readdlm(joinpath(casedir, "reference/c_driver.sel"))
            # Re-verify CLI ≡ C from committed references (cheap consistency check).
            @test isapprox(ref_cli, ref_c; rtol = 1e-8, atol = 1e-12)
            # Run Julia driver, compare to C reference.
            include(joinpath(casedir, "driver.jl"))   # defines `julia_output::Matrix`
            @test isapprox(julia_output, ref_c; rtol = 1e-8, atol = 1e-12)
        end
    end
end
```

### Benchmark suite — first-class CI infrastructure

The same reference cases drive the performance suite. Benchmarks are **not optional or maintainer-only** — they run on every pull request and every release, gate merges on regression detection, and produce diagnostic plots that are committed as artifacts and rendered in the docs.

Three benchmark tiers:

| Tier | When it runs | Scope | Plot output |
|---|---|---|---|
| **Quick** | Every PR (≤ 90 s) | 5 representative cases × `nthreads=1`; hot-loop only | Per-case sample histogram; PR-comment summary table |
| **Full**  | Every push to `main`, every release tag | All reference cases × `nthreads ∈ {1, 2, 4, 8}` × hot-loop + threading scan | Per-case histograms; cross-case overhead bars; threading-scaling curves |
| **Cross-version** | Aggregated after the matrix completes | Combines results from each Julia version in the CI matrix | Grouped bar chart per case, one bar per Julia version |

The benchmark scripts use **`CairoMakie`** (headless PNG/SVG/PDF; pure-Julia, no system deps) so plots render identically on every CI runner. Plots are saved to `benchmark/plots/` and uploaded as build artifacts; the docs page `validation/performance.md` embeds the latest ones via `Documenter`'s asset handling.

#### `PhreeqcRM/benchmark/benchmarks.jl`

```julia
using BenchmarkTools, PhreeqcRM
const SUITE = BenchmarkGroup()
SUITE["hot_loop"]         = BenchmarkGroup()       # per-case: set / run / get
SUITE["threading"]        = BenchmarkGroup()       # nthreads scan per case
SUITE["allocations"]      = BenchmarkGroup()       # @allocated per call
SUITE["wrapper_overhead"] = BenchmarkGroup()       # ratio Julia / C, computed post-run

include(joinpath(@__DIR__, "harness.jl"))          # populates SUITE from reference_suite/*
```

#### `PhreeqcRM/benchmark/harness.jl`

```julia
const CASES_DIR = joinpath(@__DIR__, "..", "test", "reference_suite")

for case in readdir(CASES_DIR; join = true)
    isdir(case) || continue
    name = basename(case)
    include(joinpath(case, "driver.jl"))           # contract: defines setup_julia(), step!(state)
    state = setup_julia()
    SUITE["hot_loop"][name]    = @benchmarkable step!($state)            samples=200 evals=1 seconds=15
    SUITE["allocations"][name] = @benchmarkable (@allocated step!($state)) samples=1   evals=1
end

for case in readdir(CASES_DIR; join = true)
    isdir(case) || continue
    occursin("transport", basename(case)) || occursin("advect", basename(case)) || occursin("momas", basename(case)) || continue
    for n in (1, 2, 4, 8)
        n ≤ Sys.CPU_THREADS || continue
        include(joinpath(case, "driver.jl"))
        state = setup_julia(; nthreads = n)
        SUITE["threading"][basename(case)]["nthreads=$n"] =
            @benchmarkable run_cells!($(state.rm)) samples=50 seconds=15
    end
end
```

#### `PhreeqcRM/benchmark/time_c_drivers.jl`

Times the compiled C drivers — same code path as `driver.c` — using a 3-run median to get a comparable wall-clock per `step()`. Output is a JSON sidecar `benchmark/c_timings.json` consumed by the plotting and ratio code. Without this, we can't compute the Julia/C ratio.

```julia
using JSON3, Statistics
const CASES_DIR = joinpath(@__DIR__, "..", "test", "reference_suite")
const BUILD_DIR = joinpath(@__DIR__, "..", "test", "c_build")
results = Dict{String, Float64}()
for case in readdir(CASES_DIR; join = true)
    isdir(case) || continue
    binname = "$(basename(case))_driver"
    binpath = joinpath(BUILD_DIR, binname)
    isfile(binpath) || (@warn "missing $binname; skipping"; continue)
    samples = Float64[]
    for _ in 1:5
        t0 = time_ns(); run(`$binpath --bench-step 200`); push!(samples, (time_ns() - t0) / 200 / 1e9)
    end
    sort!(samples)
    results[basename(case)] = samples[3]            # median of 5 runs (drivers print nothing in bench mode)
end
open(joinpath(@__DIR__, "c_timings.json"), "w") do io
    JSON3.write(io, results)
end
```

(The C drivers gain a `--bench-step N` mode that runs the hot loop `N` times silently and exits, so this script can measure per-step time without parsing output.)

#### `PhreeqcRM/benchmark/runbench.jl` (entry point)

```julia
using PkgBenchmark, BenchmarkTools, JSON3, Dates
include("plots.jl")

result = benchmarkpkg("PhreeqcRM")
BenchmarkTools.save("benchmark/latest.json", median(result.benchmarkgroup))

# Compare to committed baseline (per Julia version)
julia_tag = "v$(VERSION.major).$(VERSION.minor)"
baseline_path = "benchmark/baseline/$(julia_tag).json"
if isfile(baseline_path)
    baseline = BenchmarkTools.load(baseline_path)[1]
    judgement = judge(median(result.benchmarkgroup), baseline;
                      time_tolerance = 0.05, memory_tolerance = 0.0)   # 5% time, 0 alloc tolerance
    BenchmarkTools.save("benchmark/judge_$(julia_tag).json", judgement)
    open("benchmark/judge_summary.md", "w") do io
        export_markdown(io, judgement)
    end
    # Regression exit code → CI consumes this to fail the job
    has_regression = any(t -> t == :regression, leaves(judgement.benchmarkgroup))
    has_regression && exit(1)
end

# Render diagnostic plots
mkpath("benchmark/plots")
plot_hot_loop_per_case("benchmark/plots/hot_loop", result)
plot_threading_scaling("benchmark/plots/threading", result)
plot_allocations_bars("benchmark/plots/allocations", result)
plot_julia_vs_c_overhead("benchmark/plots/overhead", result, JSON3.read(read("benchmark/c_timings.json", String)))
```

#### `PhreeqcRM/benchmark/plots.jl` (Makie diagnostics)

```julia
using CairoMakie, BenchmarkTools, JSON3, Statistics

# Per-case sample distribution — shows variance and outliers.
function plot_hot_loop_per_case(outdir, result)
    mkpath(outdir)
    for (name, trial) in result.benchmarkgroup["hot_loop"]
        f = Figure(size = (700, 400))
        ax = Axis(f[1, 1], xlabel = "step time (μs)", ylabel = "samples",
                  title = "$name — hot loop sample distribution (n = $(length(trial.times)))")
        hist!(ax, trial.times ./ 1e3, bins = 40, strokecolor = :black, strokewidth = 0.5)
        vlines!(ax, [median(trial.times) / 1e3], color = :red, linewidth = 2, label = "median")
        axislegend(ax)
        save(joinpath(outdir, "$(name).png"), f)
    end
end

# Threading scaling — speedup vs nthreads, with ideal line.
function plot_threading_scaling(outdir, result)
    mkpath(outdir)
    for (case, group) in result.benchmarkgroup["threading"]
        ns = sort([parse(Int, last(split(k, "="))) for k in keys(group)])
        ts = [median(group["nthreads=$n"].times) for n in ns]
        speedup = ts[1] ./ ts
        f = Figure(size = (700, 400))
        ax = Axis(f[1, 1], xlabel = "nthreads", ylabel = "speedup vs nthreads=1",
                  title = "$case — strong scaling", xticks = ns)
        lines!(ax, ns, ns, color = :gray, linestyle = :dash, label = "ideal")
        scatterlines!(ax, ns, speedup, color = :blue, marker = :circle, label = "measured")
        axislegend(ax, position = :lt)
        save(joinpath(outdir, "$(case).png"), f)
    end
end

# Wrapper overhead summary — Julia time / C time per case.
function plot_julia_vs_c_overhead(outpath, result, c_timings)
    cases = collect(keys(c_timings))
    j_times = [median(result.benchmarkgroup["hot_loop"][c].times) / 1e9 for c in cases]
    c_times = [c_timings[c] for c in cases]
    ratio = j_times ./ c_times
    f = Figure(size = (max(700, 60 * length(cases)), 450))
    ax = Axis(f[1, 1], xlabel = "case", ylabel = "Julia / C step time",
              title = "Wrapper overhead ratio (target < 1.10)",
              xticks = (1:length(cases), cases), xticklabelrotation = π/4)
    barplot!(ax, 1:length(cases), ratio, color = ifelse.(ratio .< 1.10, :seagreen, :tomato))
    hlines!(ax, [1.10], color = :red, linestyle = :dash, label = "10% overhead budget")
    hlines!(ax, [1.00], color = :gray, linestyle = :dot,  label = "parity with C")
    axislegend(ax)
    save("$(outpath)_summary.png", f)
end

# Allocation bars — per-case @allocated per step (target: 0).
function plot_allocations_bars(outpath, result) ; end   # similar pattern

# Cross-Julia-version comparison — called from the CI aggregation job.
# Reads multiple latest.json from {julia-1.10, julia-1, nightly} and emits a grouped bar plot.
function plot_cross_julia_versions(outpath, result_paths_by_version)
    versions = collect(keys(result_paths_by_version))
    all_results = Dict(v => BenchmarkTools.load(p)[1] for (v, p) in result_paths_by_version)
    # ... extract per-case times across versions, render grouped bar ...
end

# Historical trend — reads benchmark-history/ for the same case, plots time vs commit.
function plot_history_trend(outpath, case_name, history_dir) ; end
```

#### Regression-tracking workflow

- **Baselines**: `benchmark/baseline/v1.10.json`, `benchmark/baseline/v1.11.json`, `benchmark/baseline/nightly.json` — one per supported Julia version, committed to the repo. Updated only on release tags (`v0.x.0`) via a manual workflow.
- **Per-PR judge**: `runbench.jl` runs the **Quick** tier on the PR, judges against the matching baseline with `time_tolerance = 0.05, memory_tolerance = 0.0`, and **exits non-zero on any `:regression` leaf**. CI surfaces this as a failed status check; PR cannot merge until the regression is explained or fixed.
- **PR comment**: a separate workflow step (`bench-comment.yml`) reads `benchmark/judge_summary.md` and the plots from `benchmark/plots/`, posts them as a PR comment with embedded images. Format:
  ```
  | Case | PR median | main median | Δ% | Verdict |
  | --- | --- | --- | --- | --- |
  | ex11_transport_exchange | 482 μs | 470 μs | +2.5% | OK |
  | ex09_kinetics | 1.31 ms | 1.18 ms | +11% | ⚠️ REGRESSION |
  ```
- **Historical store**: a `benchmark-history` orphan branch stores `latest.json` keyed by `<julia-version>/<commit-sha>.json`. On `main` push, CI appends. `plot_history_trend` reads from this branch in the docs build, emits per-case time-vs-commit trends, embedded in `validation/performance.md`.
- **Allocation lock**: `memory_tolerance = 0.0` means **any** new allocation in a hot-loop entry blocks the merge. This is the strongest knob in `BenchmarkTools.judge`; combined with the `@testitem tags=[:perf]` allocation tests, it makes regressing toward allocating code physically uncomfortable.

#### Plot inventory

| File | What it shows | When regenerated |
|---|---|---|
| `plots/hot_loop/<case>.png` | Sample-time histogram per case with median line | Every benchmark run |
| `plots/threading/<case>.png` | Strong scaling curve (nthreads vs speedup) vs ideal line | Full + cross-version runs |
| `plots/overhead_summary.png` | Bar chart of Julia/C ratio per case, 1.10 budget line | Every benchmark run |
| `plots/allocations.png` | Bar chart of `@allocated` per case (zero bars expected) | Every benchmark run |
| `plots/julia_versions.png` | Grouped bars: each case × each Julia version | Cross-version aggregation job |
| `plots/history/<case>.png` | Time-vs-commit trend over last N main-pushes | Docs build (reads benchmark-history) |

#### Compilation awareness (unchanged)

- `BenchmarkTools.@benchmarkable ... samples=N evals=M`: first sample discarded, so first-call compile time doesn't pollute medians.
- `@allocated step!(state)` is always preceded by one warmup call (codified in `@testitem tags=[:perf]` and in `harness.jl`).
- `BenchmarkTools.tune!(SUITE)` runs once; output committed to `benchmark/params.json` so CI runs are reproducible.
- We report **median**, not minimum.

## Phased execution

### Phase 0 — Build `libphreeqcrm` locally

`deps/build_phreeqcrm.sh`:
1. `git clone --depth 1 --branch <pinned-tag> https://github.com/usgs-coupled/phreeqcrm deps/src`.
2. `cmake -S deps/src -B deps/build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DPHREEQCRM_BUILD_SHARED=ON -DPHREEQCRM_BUILD_TESTS=OFF -DCMAKE_INSTALL_PREFIX="$PWD/deps/usr" -DCMAKE_INSTALL_RPATH="@loader_path"`.
3. `cmake --build deps/build -j && cmake --install deps/build`.
4. Result: `deps/usr/lib/libphreeqcrm.dylib`. Document `export JULIA_PHREEQCRM_PATH="$PWD/deps/usr/lib/libphreeqcrm.dylib"` in `deps/README.md`.

MPI off; OpenMP at upstream default (threads capped from Julia via `RM_SetThreadCount`).

### Phase 1 — Bootstrap with `Pkg`, then stub JLL + generator

**No hand-written `Project.toml` files.** Use `Pkg.generate` and `Pkg.add` for everything; the resulting manifests are authoritative.

```bash
# From the workspace root.
cd /Users/vcantarella/wc/phreeqc_in_julia

# 1. Generate the stub JLL package.
julia -e 'using Pkg; Pkg.generate("PhreeqcRM_jll")'
# Edit only src/PhreeqcRM_jll.jl with the const libphreeqcrm body shown earlier.
# Add the one runtime dep:
julia --project=PhreeqcRM_jll -e 'using Pkg; Pkg.add("Libdl")'

# 2. Generate the wrapper package.
julia -e 'using Pkg; Pkg.generate("PhreeqcRM")'
julia --project=PhreeqcRM -e '
    using Pkg
    Pkg.develop(path = "PhreeqcRM_jll")     # local stub becomes the dep
    Pkg.add("Libdl")
'

# 3. Generator project — pins Clang.jl independently from the main project.
mkdir -p PhreeqcRM/gen
julia --project=PhreeqcRM/gen -e '
    using Pkg
    Pkg.activate("PhreeqcRM/gen")
    Pkg.add("Clang")
'

# 4. Test deps (TestItems-based suite).
julia --project=PhreeqcRM -e '
    using Pkg
    Pkg.add(["TestItems", "TestItemRunner", "BenchmarkTools", "Aqua"])
    Pkg.add(name = "Test", uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40")   # stdlib
'

# 5. Weakdeps + extensions (DataFrames support without forcing the dep).
julia --project=PhreeqcRM -e '
    using Pkg
    # weakdeps must be edited into Project.toml after `Pkg.add`; Pkg does not yet expose a CLI verb.
    # Use Pkg.compat first, then edit [weakdeps] / [extensions] manually as the only Project.toml hand-edit.
'
```

Hand-editing the `Project.toml` is reserved for `[weakdeps]` and `[extensions]` blocks (which Pkg does not yet manage from the CLI). All version compats live in `[compat]` and are populated via `Pkg.compat(...)`.

**Generator step (committed output):**

`PhreeqcRM/gen/generator.jl` (skeleton):
```julia
using Clang.Generators
ctx = create_context(
    [joinpath(@__DIR__, "include", "RM_interface_C.h")],
    get_default_args(),
    load_options(joinpath(@__DIR__, "generator.toml")),
)
build!(ctx)
```
`PhreeqcRM/gen/generator.toml`:
```toml
[general]
library_name = "libphreeqcrm"
output_file_path = "../src/LibPhreeqcRM.jl"
module_name = "LibPhreeqcRM"
jll_pkg_name = "PhreeqcRM_jll"
export_symbol_prefixes = ["RM_", "IRM_"]
```

`jll_pkg_name = "PhreeqcRM_jll"` is what makes generated `@ccall`s resolve through `PhreeqcRM_jll.libphreeqcrm`. When the real Yggdrasil JLL ships, the generated bindings need **no regeneration** — only the local stub package is swapped out.

Regeneration command (maintainer-only, not run on user install):
```bash
julia --project=PhreeqcRM/gen PhreeqcRM/gen/generator.jl
```

### Phase 2 — Idiomatic Julia layer

- `errors.jl`: `@enum IRMResult IRM_OK=0 …`; `PhreeqcRMError <: Exception`; `check_result(rc, rm)` queries `RM_GetErrorStringLength` then `RM_GetErrorString`, throws on non-`IRM_OK`.
- `units.jl`: separate `@enum` per unit domain — `SolutionUnits`, `PPAssemblageUnits`, `ExchangeUnits`, `SurfaceUnits`, `GasPhaseUnits`, `SSAssemblageUnits`, `KineticsUnits`. Upstream integer codes overlap with different meanings — do not share.
- `instance.jl`: `mutable struct PhreeqcRMInstance` holding `id::Cint`, `nxyz::Int`, `nthreads::Int`, `ncomps::Int` (0 until `find_components!`), `components::Vector{String}` cache, `destroyed::Bool` flag. Constructor calls `RM_Create` then `RM_SetComponentH2O` (must precede `LoadDatabase`). `Base.close` is the primary teardown (guards `destroyed`); finalizer just calls `close` if `!destroyed`. `with_instance` do-block helper for RAII.
- `components.jl`: `load_database!`, `run_file!`, `run_string!`, `find_components!` (caches `ncomps` and names, asserts called before any concentration op).
- `concentrations.jl`: shape contract is `Matrix{Float64}(nxyz, ncomps)`. `zeros_concentrations`, `get_concentrations!`, `set_concentrations!` validate `size(c) == (ncomps, nxyz)` and pass `vec(c)` (zero-copy). Each `set_concentrations!` / `run_cells!` asserts required upstream calls were made.
- `selected_output.jl`: on first `get_selected_output(rm)`, cache column count + headings. Return `NamedTuple{Symbol.(headings)}(cols)`. Each call refreshes the values, not the schema.
- `transport.jl`: `with_instance`, `bycell`, `set_initial_conditions!`, `initial_phreeqc_to_concentrations`.
- `ext/PhreeqcRMDataFramesExt.jl`: package extension; provides `DataFrame(out::SelectedOutput)` when DataFrames is loaded.

### Phase 3 — End-to-end validation

`examples/advection_reaction.jl` — port the 1D advection-reaction SNIA example from the upstream PhreeqcRM distribution (`advect.pqi`):
- 40 cells, upwind explicit advection on the Julia side.
- PhreeqcRM does the reaction substep per timestep.
- Inflow boundary from solution 0, initial cell water from solution 1.
- Final concentration vector compared against the upstream sample's reference output, tolerance ~1e-8.

Exercises the entire lifecycle and the concentration shape contract.

### Phase 4 — Tests, allocation guards, threading, benchmarks (TestItems-based, TDD)

Use **`TestItems.jl`** + **`TestItemRunner.jl`** so individual test items are independently runnable from the VS Code Julia extension or the CLI, and so we can drive the implementation in a TDD style: write the failing `@testitem` first, then implement.

**`PhreeqcRM/test/runtests.jl`** (entire content):
```julia
using TestItemRunner
@run_package_tests
```

Test files under `PhreeqcRM/test/` hold `@testitem` and `@testsetup` blocks. Tags partition the suite: `:fast` (default), `:perf` (allocation regressions, run separately), `:threads` (threading correctness, run with `JULIA_NUM_THREADS≥2`), `:bench` (benchmarks, opt-in only).

**`PhreeqcRM/test/setup.jl`** — shared fixtures via `@testsetup`:
```julia
@testsetup module Fixtures
    using PhreeqcRM
    const DB = "/usr/local/share/doc/phreeqc/database/phreeqc.dat"

    function trivial_rm(nxyz = 10; nthreads = 1)
        rm = PhreeqcRMInstance(nxyz; nthreads)
        load_database!(rm, DB)
        run_string!(rm, """
            SOLUTION 1
                pH 7.0
                Na 1.0
                Cl 1.0 charge
            END
        """)
        set_units!(rm; solution = SolutionUnits.MolPerL)
        set_porosity!(rm, fill(0.3, nxyz))
        set_saturation!(rm, fill(1.0, nxyz))
        set_representative_volume!(rm, fill(1.0, nxyz))
        set_temperature!(rm, fill(25.0, nxyz))
        set_pressure!(rm, fill(1.0, nxyz))
        find_components!(rm)
        set_initial_conditions!(rm; solution = fill(1, nxyz))
        set_time!(rm, 0.0); set_time_step!(rm, 1.0)
        return rm
    end
end
```

**Test coverage (one file per group):**

`test/test_lifecycle.jl`:
```julia
@testitem "Create + close lifecycle" begin
    rm = PhreeqcRMInstance(10)
    @test isvalid(rm)
    close(rm)
    @test !isvalid(rm)
end

@testitem "Double close is idempotent" begin
    rm = PhreeqcRMInstance(10)
    close(rm); close(rm)         # second is a no-op
    @test !isvalid(rm)
end

@testitem "with_instance closes on exception" begin
    rm_ref = Ref{PhreeqcRMInstance}()
    @test_throws ErrorException PhreeqcRM.with_instance(10) do rm
        rm_ref[] = rm
        error("boom")
    end
    @test !isvalid(rm_ref[])
end
```

`test/test_errors.jl`:
```julia
@testitem "IRM_RESULT translates to PhreeqcRMError" setup=[Fixtures] begin
    rm = PhreeqcRMInstance(1)
    @test_throws PhreeqcRMError load_database!(rm, "/nonexistent.dat")
    close(rm)
end
```

`test/test_concentrations.jl`:
```julia
@testitem "Shape contract for concentration matrix" setup=[Fixtures] begin
    rm = Fixtures.trivial_rm(40)
    c = zeros_concentrations(rm)
    @test size(c) == (ncomps(rm), nxyz(rm))
    bad = zeros(nxyz(rm), ncomps(rm))               # wrong order
    @test_throws DimensionMismatch set_concentrations!(rm, bad)
    close(rm)
end

@testitem "Round-trip preserves values at Δt=0" setup=[Fixtures] begin
    rm = Fixtures.trivial_rm(1)
    c = zeros_concentrations(rm)
    get_concentrations!(rm, c)
    c0 = copy(c)
    set_concentrations!(rm, c)
    set_time_step!(rm, 0.0)
    run_cells!(rm)
    get_concentrations!(rm, c)
    @test c ≈ c0 rtol = 1e-12
    close(rm)
end
```

`test/test_allocations.jl` (the `:perf` set — uses `@allocated` after a warmup; zero is the bar):
```julia
@testitem "set_concentrations! does zero allocations" tags=[:perf] setup=[Fixtures] begin
    rm = Fixtures.trivial_rm(100)
    c = zeros_concentrations(rm)
    set_concentrations!(rm, c)                       # warmup, also forces TLS for ccall
    @test (@allocated set_concentrations!(rm, c)) == 0
    close(rm)
end

@testitem "get_concentrations! does zero allocations" tags=[:perf] setup=[Fixtures] begin
    rm = Fixtures.trivial_rm(100)
    c = zeros_concentrations(rm)
    get_concentrations!(rm, c)
    @test (@allocated get_concentrations!(rm, c)) == 0
    close(rm)
end

@testitem "run_cells! does zero allocations" tags=[:perf] setup=[Fixtures] begin
    rm = Fixtures.trivial_rm(100)
    run_cells!(rm)                                   # warmup
    @test (@allocated run_cells!(rm)) == 0
    close(rm)
end

@testitem "Hot loop has bounded per-iter allocation" tags=[:perf] setup=[Fixtures] begin
    rm = Fixtures.trivial_rm(1000)
    c = zeros_concentrations(rm)
    function step!(rm, c)
        set_concentrations!(rm, c)
        run_cells!(rm)
        get_concentrations!(rm, c)
    end
    step!(rm, c)                                     # warmup
    @test (@allocated step!(rm, c)) == 0
    close(rm)
end
```
Allocation tests guard against accidental boxing, splat-allocating tuples, transient temporaries from broadcasts, etc. — common silent regressions in numerical Julia.

`test/test_threading.jl` (the `:threads` set — requires `julia -t auto`):
```julia
@testitem "OMP thread count honored" tags=[:threads] begin
    rm = PhreeqcRMInstance(100; nthreads = 1)
    @test thread_count(rm) == 1
    close(rm)
    rm = PhreeqcRMInstance(100; nthreads = 4)
    @test thread_count(rm) == 4
    close(rm)
end

@testitem "Two instances driven from two Julia threads agree with serial" tags=[:threads] setup=[Fixtures] begin
    Threads.nthreads() ≥ 2 || return            # skip if single-threaded run
    rm_par = [Fixtures.trivial_rm(50; nthreads = 1) for _ in 1:2]
    rm_ref = Fixtures.trivial_rm(50; nthreads = 1)

    results = Vector{Matrix{Float64}}(undef, 2)
    Threads.@threads for i in 1:2
        rm = rm_par[i]
        run_cells!(rm)
        results[i] = get_concentrations(rm)
    end
    run_cells!(rm_ref)
    ref = get_concentrations(rm_ref)
    @test results[1] ≈ ref rtol = 1e-10
    @test results[2] ≈ ref rtol = 1e-10
    foreach(close, rm_par); close(rm_ref)
end

@testitem "Oversubscription warning fires when nthreads × Julia threads > CPU count" tags=[:threads] begin
    Threads.nthreads() ≥ 2 || return
    @test_logs (:warn, r"oversubscription") PhreeqcRMInstance(10; nthreads = Sys.CPU_THREADS)
end
```

`test/test_advect_reference.jl` (golden integration test):
```julia
@testitem "1D advection-reaction matches reference" tags=[:integration] begin
    include(joinpath(@__DIR__, "..", "examples", "advection_reaction.jl"))
    ref = readdlm(joinpath(@__DIR__, "reference", "advect_final.dat"))
    @test final_concentrations ≈ ref rtol = 1e-8
end
```

`test/test_aqua.jl`:
```julia
@testitem "Aqua quality checks" tags=[:fast] begin
    using Aqua
    Aqua.test_all(PhreeqcRM; ambiguities = false)
end
```

**Benchmarks (`PhreeqcRM/benchmark/`):**

Separate from tests — a `BenchmarkTools.BenchmarkGroup` suite, runnable manually, also exposed as a tagged `@testitem` in `test/test_benchmarks.jl` that does a smoke run (single sample, asserts the entry didn't error) so the benchmark code is kept compiling.

`PhreeqcRM/benchmark/Project.toml` — separate project; `Pkg.add` `BenchmarkTools`, `PkgBenchmark`, and `Pkg.develop` the wrapper.

`PhreeqcRM/benchmark/benchmarks.jl`:
```julia
using BenchmarkTools, PhreeqcRM

const SUITE = BenchmarkGroup()

let rm = setup_for_bench(1000)
    c = zeros_concentrations(rm)
    SUITE["hot_loop"]["set_concentrations"]  = @benchmarkable set_concentrations!($rm, $c)
    SUITE["hot_loop"]["run_cells"]           = @benchmarkable run_cells!($rm)
    SUITE["hot_loop"]["get_concentrations"]  = @benchmarkable get_concentrations!($rm, $c)
end

SUITE["threading"] = BenchmarkGroup()
for n in (1, 2, 4, 8)
    rm = setup_for_bench(10000; nthreads = n)
    SUITE["threading"]["nthreads=$n"] = @benchmarkable run_cells!($rm)
end
```

Run with `julia --project=PhreeqcRM/benchmark -e 'using PkgBenchmark; r = benchmarkpkg("PhreeqcRM"); export_markdown("bench.md", r)'`. Track regressions by committing baseline JSON, comparing on demand.

**Running the suites:**

```bash
# Default suite (fast)
julia --project=PhreeqcRM -e 'using TestItemRunner; @run_package_tests filter = ti -> !(:perf in ti.tags || :threads in ti.tags || :bench in ti.tags)'

# Allocation regressions
julia --project=PhreeqcRM -e 'using TestItemRunner; @run_package_tests filter = ti -> :perf in ti.tags'

# Threading correctness (requires multi-threaded Julia)
julia -t auto --project=PhreeqcRM -e 'using TestItemRunner; @run_package_tests filter = ti -> :threads in ti.tags'

# All non-bench
julia -t auto --project=PhreeqcRM -e 'using TestItemRunner; @run_package_tests filter = ti -> !(:bench in ti.tags)'
```

**TDD workflow**: for each entry in the public API (Function reference section), write the corresponding `@testitem` first, watch it fail with a `MethodError` or `UndefVarError`, then implement the minimum that makes it pass. The allocation tests pin down the performance contract from day one — if a refactor breaks zero-alloc, the test fires.

**CI**: deferred until a Yggdrasil-built `PhreeqcRM_jll` exists. Locally, `JULIA_PHREEQCRM_PATH` must be set before running any suite; the test harness errors loudly if it isn't (`PhreeqcRM_jll.libphreeqcrm` would already have errored at load time).

### Phase 5 — Documentation (Documenter.jl)

Build hosted docs from day one — the API is large enough that scrolling through README.md and grepping docstrings is not sufficient.

Layout:

```
PhreeqcRM/docs/
  Project.toml                      # Pkg-managed: Documenter, PhreeqcRM (Pkg.dev), DocumenterTools
  make.jl                           # builds + (in CI) deploys to gh-pages
  src/
    index.md                        # what is PhreeqcRM, why a Julia wrapper, links
    installation.md                 # building libphreeqcrm locally; future JLL path
    concepts/
      phreeqc_vs_phreeqcrm.md       # the conceptual split (lifted from the plan)
      memory_model.md               # ownership ledger + array layout (with diagram)
      threading.md                  # Patterns A/B/C, defaults, safety contract
      lifecycle.md                  # mandatory call order with the state diagram
    tutorials/
      01_first_run.md               # speciation calc using Ex 1
      02_coupling_transport.md      # the EXCHANGE column from the plan, end-to-end
      03_kinetics.md                # using a KINETICS + RATES script
      04_parallelism.md             # walking through Pattern A → B → C
    reference/
      api.md                        # @autodocs for the public API
      lib.md                        # auto-generated for LibPhreeqcRM (collapsed by default)
    validation/
      methodology.md                # the three-way pipeline
      results.md                    # auto-generated table of CLI≡C≡Julia status per case
      performance.md                # auto-generated table from bench_report.md
    devnotes/
      adding_a_test_case.md         # mechanical instructions for the reference suite
      regenerating_bindings.md      # when and how to re-run Clang.jl
      releasing.md                  # version bump + JLL coordination
  generate_validation_md.jl         # called by make.jl; reads test results, emits validation/results.md
  generate_performance_md.jl        # called by make.jl; reads bench JSON, emits validation/performance.md
```

`docs/make.jl`:
```julia
using Documenter, PhreeqcRM
include("generate_validation_md.jl"); generate_validation_md()
include("generate_performance_md.jl"); generate_performance_md()
makedocs(
    sitename = "PhreeqcRM.jl",
    modules  = [PhreeqcRM],
    pages    = [
        "Home" => "index.md",
        "Installation" => "installation.md",
        "Concepts" => [
            "PHREEQC vs PhreeqcRM" => "concepts/phreeqc_vs_phreeqcrm.md",
            "Memory & layout"      => "concepts/memory_model.md",
            "Threading"            => "concepts/threading.md",
            "Lifecycle"            => "concepts/lifecycle.md",
        ],
        "Tutorials" => [
            "First run"          => "tutorials/01_first_run.md",
            "Coupling transport" => "tutorials/02_coupling_transport.md",
            "Kinetics"           => "tutorials/03_kinetics.md",
            "Parallelism"        => "tutorials/04_parallelism.md",
        ],
        "Reference" => ["API" => "reference/api.md", "Low-level" => "reference/lib.md"],
        "Validation" => [
            "Methodology" => "validation/methodology.md",
            "Results"     => "validation/results.md",
            "Performance" => "validation/performance.md",
        ],
        "Developer notes" => [
            "Adding a test case"     => "devnotes/adding_a_test_case.md",
            "Regenerating bindings"  => "devnotes/regenerating_bindings.md",
            "Releasing"              => "devnotes/releasing.md",
        ],
    ],
    checkdocs = :exports,
    warnonly  = false,
)
deploydocs(repo = "github.com/<user>/PhreeqcRM.jl.git", devbranch = "main")
```

**Docstring policy:** every exported function in the public API must have a docstring including signature, behavior, expected array shapes, and one example. `Documenter.makedocs(..., checkdocs = :exports, warnonly = false)` fails the build if any export lacks one. This ratchets coverage.

**Auto-generated validation page**: `generate_validation_md.jl` reads the latest reference-suite test results (a JSON the test harness drops in `test/results.json`) and produces a markdown table — one row per case, columns: CLI vs C, C vs Julia, max-error, status (✓/✗). Means the docs always show the current numerical health of every case.

**Auto-generated performance page**: `generate_performance_md.jl` reads `benchmark/latest.json` and `benchmark/baseline.json`, produces a table per case: median Julia step time, median C step time, Julia/C ratio, allocations. Same auto-update story.

**Doctests:** code blocks in tutorials are run via `Documenter.doctest!` to ensure they stay in sync with the API.

### Phase 6 — Continuous integration (GitHub Actions)

CI exercises the same pipeline a user would, with benchmarks treated as a first-class merge gate — not a manual or scheduled afterthought.

#### Workflows

`.github/workflows/CI.yml` — runs on every push and pull request. Jobs:

1. **build-libphreeqcrm** — matrix over `{ubuntu-latest, macos-latest, windows-latest}`.
   - Caches the CMake build of `usgs-coupled/phreeqcrm` keyed on its commit SHA + cmake flags + OS (saves ~3 min per re-run).
   - Uploads the resulting `libphreeqcrm.{so,dylib,dll}` as a job artifact.
2. **test** — needs `build-libphreeqcrm`; matrix over `{ubuntu-latest, macos-latest, windows-latest}` × `{julia-1.10, julia-1, nightly}` × `{threads=1, threads=4}`.
   - Downloads the libphreeqcrm artifact; exports `JULIA_PHREEQCRM_PATH`.
   - Builds C drivers: `make -C PhreeqcRM/test/c_build`.
   - Installs PHREEQC CLI for the reference suite (apt/brew/choco depending on OS).
   - Runs `@run_package_tests` filters: `:fast`, `:perf`, `:threads` (only when `JULIA_NUM_THREADS ≥ 2`), `:integration`.
   - Uploads `test/results.json` and logs as artifacts on failure.
   - Codecov upload via `julia-actions/julia-processcoverage`.
3. **aqua** — repeats the Aqua testitem as a standalone fast job that fails the PR early on naming / ambiguity issues.
4. **format** — `JuliaFormatter` in check mode; advisory, non-blocking.
5. **docs** — needs `test`. `julia --project=docs docs/make.jl`. On PRs: builds without deploying (catches doc breakage; missing docstrings fail the build). On `main` pushes: deploys to `gh-pages` via `deploydocs`.

`.github/workflows/Benchmark-Quick.yml` — runs on **every pull request**.

- Single runner: `ubuntu-latest-4core` (fixed CPU class so timings are comparable across PRs).
- Matrix over `{julia-1.10, julia-1}` (skip nightly here — too noisy for blocking judgment).
- Steps:
  1. Build / cache `libphreeqcrm`.
  2. Build C drivers (`make -C PhreeqcRM/test/c_build`).
  3. Time C drivers: `julia --project=PhreeqcRM/benchmark PhreeqcRM/benchmark/time_c_drivers.jl` → `benchmark/c_timings.json`.
  4. Run Quick tier: `julia --project=PhreeqcRM/benchmark PhreeqcRM/benchmark/runbench.jl --tier=quick` → `benchmark/latest.json` + plots in `benchmark/plots/`.
  5. **`runbench.jl` exits non-zero on any `:regression` leaf from `BenchmarkTools.judge` (`time_tolerance = 0.05, memory_tolerance = 0.0`).** This fails the workflow → blocks the merge.
  6. Upload `benchmark/plots/` and `benchmark/judge_summary.md` as artifacts.

`.github/workflows/Benchmark-Full.yml` — runs on **every push to `main`** and on **release tag**.

- Same fixed runner class.
- Matrix over `{julia-1.10, julia-1, nightly}` × `{threads = 1, 4, 8}`.
- Runs Full tier: all reference cases × full threading scan.
- On `main` push: appends `benchmark/latest.json` to the `benchmark-history` orphan branch keyed by `<julia-version>/<commit-sha>.json`.
- On release tag: also updates `benchmark/baseline/<julia-version>.json` in the same commit as the release (manual approval gate).
- Runs a cross-version aggregation step at the end of the matrix:
  - Collects every `latest.json` from the matrix into one place.
  - Runs `plot_cross_julia_versions(...)` → `plots/julia_versions.png`.
  - Runs `plot_history_trend(...)` for each case using `benchmark-history` → `plots/history/<case>.png`.
  - Uploads everything as artifacts; the `docs` job consumes them on its next run.

`.github/workflows/Benchmark-Comment.yml` — runs after `Benchmark-Quick.yml` completes on a PR.

- Downloads the Quick-tier artifacts (judge summary, plots).
- Posts (or updates if a previous comment exists) a PR comment containing:
  - The judge summary table (per-case PR median, main baseline median, Δ%, verdict).
  - Inline plots: `overhead_summary.png`, the four hot-loop histograms for the cases that moved most.
- Uses the `peter-evans/find-comment` + `peter-evans/create-or-update-comment` pattern so the comment is edited in place across pushes.

`.github/workflows/CompatHelper.yml` / `TagBot.yml` — standard Julia ecosystem boilerplate from the General registry templates.

`.github/dependabot.yml` — keeps action versions current.

#### Regression policy

- **Quick tier on every PR is a merge gate**. A regression (> 5% time on any case, or any new allocation in a hot-loop case) fails the workflow and blocks the merge until either: the regression is fixed, the baseline is intentionally updated (release process), or the PR explicitly bumps `benchmark/baseline/*.json` with reviewer-visible diff.
- **Full tier on `main` and on release** updates trend data but doesn't block (nothing to block — already merged). Regressions detected here generate a GitHub issue automatically via `actions/github-script`.
- **Cross-version plots** make it visible at a glance when a new Julia version regresses our hot path — useful when nightly starts diverging before a major release.

#### Plot integration into docs

The `docs` job, after `test` and `Benchmark-Full` complete, downloads the latest plots and copies them into `docs/src/assets/benchmarks/`. `docs/src/validation/performance.md` references them with normal Markdown image syntax. The `generate_performance_md.jl` helper updates the page's tables from `latest.json` and `judge_*.json` in the same step.

#### Secrets and CI cost

- `DOCUMENTER_KEY` for gh-pages deploy. No other external secrets.
- README badges: CI status, docs stable/dev, Codecov, and a benchmark-status badge linking to the latest `Benchmark-Full` run.
- Cost discipline: build cache (~3 min saved per re-run); `:perf` only on Linux; benchmark jobs use a fixed runner class so we don't pay for the largest tier on every PR; nightly Julia is `continue-on-error: true` for tests but **excluded** from the Quick benchmark gate (too noisy to block on).

## Critical files to create

Files generated by `Pkg.generate` / `Pkg.add` / `Pkg.develop` are not listed here — Pkg owns them. Manifest files (`Manifest.toml`) likewise. Only files we hand-author or generate via our own scripts are listed.

```
deps/
  build_phreeqcrm.sh                          # Phase 0 build script
  README.md                                   # how to build + export JULIA_PHREEQCRM_PATH

PhreeqcRM_jll/
  src/PhreeqcRM_jll.jl                        # ~30-line stub mimicking JLLWrappers output

PhreeqcRM/
  gen/
    generator.jl                              # Clang.jl driver
    generator.toml                            # Clang.jl config (library_name, jll_pkg_name)
    include/RM_interface_C.h                  # vendored at pinned upstream tag
  src/
    PhreeqcRM.jl                              # top-level module, reexports
    LibPhreeqcRM.jl                           # GENERATED by gen/generator.jl — committed
    errors.jl                                 # IRMResult enum + PhreeqcRMError + check_result
    units.jl                                  # per-domain @enum types
    instance.jl                               # PhreeqcRMInstance + close + finalizer + with_instance
    components.jl                             # load_database!, run_file!, run_string!, find_components!
    concentrations.jl                         # zeros_concentrations, set/get_concentrations!
    selected_output.jl                        # column cache + NamedTuple result
    transport.jl                              # set_initial_conditions!, initial_phreeqc_to_concentrations, bycell
    threading.jl                              # thread_count, oversubscription warning, set_thread_count!
  ext/
    PhreeqcRMDataFramesExt.jl                 # DataFrame view of selected output
  examples/
    advection_reaction.jl                     # 1D SNIA port of advect.pqi
    exchange_column.jl                        # the worked example from the plan
  test/
    runtests.jl                               # one-liner: @run_package_tests
    setup.jl                                  # @testsetup Fixtures
    test_lifecycle.jl
    test_errors.jl
    test_concentrations.jl
    test_allocations.jl                       # tags=[:perf]
    test_threading.jl                         # tags=[:threads]
    test_reference_suite.jl                   # tags=[:integration] — drives the three-way pipeline
    test_aqua.jl
    test_benchmarks.jl                        # tags=[:bench] — smoke run of benchmark SUITE
    reference_suite/
      regenerate.jl                           # maintainer-only: refreshes reference/*.sel
      ex01_speciation/
        input.pqi, driver.c, driver.jl, README.md, reference/{phreeqc_cli.sel, c_driver.sel}
      ex02_equilibrium_phases/ … same shape …
      ex03_mixing/                  ex04_titration/
      ex05_irreversible/            ex06_reaction_path/
      ex07_gas_phase/               ex08_exchange/
      ex09_kinetics/                ex10_solid_solutions/
      ex11_transport_exchange/      ex12_kinetic_transport/
      ex13_biodegradation/          ex14_surface_complex/
      ex15_kinetic_oxidation/       ex17_isotopes/
      ex19_gas_exchange/            ex22_pitzer/
      advect_simple/                momas_easy_1d/                 momas_medium_1d/
    c_build/Makefile                          # builds every driver.c against deps/usr/lib/libphreeqcrm
    results.json                              # written by harness; consumed by docs/generate_validation_md.jl
  benchmark/
    Project.toml                              # Pkg-managed; BenchmarkTools, PkgBenchmark, CairoMakie, JSON3
    benchmarks.jl                             # SUITE definition
    harness.jl                                # populates SUITE from reference_suite/*
    plots.jl                                  # CairoMakie diagnostic + summary + cross-version plots
    time_c_drivers.jl                         # times compiled C drivers, writes c_timings.json
    runbench.jl                               # entry point: tiers (quick|full), judge, plots, exit code
    params.json                               # BenchmarkTools.tune! output, committed
    baseline/                                 # committed median baselines, one per Julia version
      v1.10.json
      v1.11.json
      nightly.json                            # informational, not used for blocking
    latest.json                               # per-run; consumed by docs/generate_performance_md.jl
    c_timings.json                            # per-run; produced by time_c_drivers.jl
    judge_v1.10.json                          # per-run; produced by runbench.jl
    judge_summary.md                          # per-run; consumed by Benchmark-Comment.yml
    plots/                                    # per-run; uploaded as CI artifacts
      hot_loop/<case>.png
      threading/<case>.png
      overhead_summary.png
      allocations.png
      julia_versions.png                      # cross-version aggregation only
      history/<case>.png                      # docs build only (reads benchmark-history branch)
  docs/
    Project.toml                              # Pkg-managed; Documenter
    make.jl                                   # docs build + deploy
    generate_validation_md.jl                 # writes validation/results.md from test/results.json
    generate_performance_md.jl                # writes validation/performance.md from benchmark/latest.json
    src/index.md                              # landing page
    src/installation.md
    src/concepts/{phreeqc_vs_phreeqcrm,memory_model,threading,lifecycle}.md
    src/tutorials/{01_first_run,02_coupling_transport,03_kinetics,04_parallelism}.md
    src/reference/{api,lib}.md
    src/validation/{methodology,results,performance}.md
    src/devnotes/{adding_a_test_case,regenerating_bindings,releasing}.md

.github/
  workflows/CI.yml                            # build-libphreeqcrm → test (matrix) → aqua → format → docs
  workflows/Benchmark-Quick.yml               # every PR; ≤90 s; regression-blocking
  workflows/Benchmark-Full.yml                # every main push + release tag; full matrix + cross-version
  workflows/Benchmark-Comment.yml             # post-PR-bench: posts summary table + plots as PR comment
  workflows/CompatHelper.yml                  # standard
  workflows/TagBot.yml                        # standard
  dependabot.yml
```

Plus an orphan branch `benchmark-history` (not in the file tree above) containing only `<julia-version>/<commit-sha>.json` files, appended by `Benchmark-Full.yml`.

Project.toml files are generated by `Pkg.generate`; we only hand-edit them to add `[weakdeps]` + `[extensions]` (which the Pkg CLI doesn't yet manage).

## Verification

Build & symbol checks:
1. `bash deps/build_phreeqcrm.sh` produces `deps/usr/lib/libphreeqcrm.dylib`. `otool -L` shows `@loader_path` rpath; `nm -gU … | grep RM_Create` finds the symbol.
2. `JULIA_PHREEQCRM_PATH=$PWD/deps/usr/lib/libphreeqcrm.dylib julia --project=PhreeqcRM -e 'using PhreeqcRM; rm = PhreeqcRMInstance(1); close(rm)'` loads, creates, destroys cleanly with no warnings.

Generator determinism:

3. `julia --project=PhreeqcRM/gen PhreeqcRM/gen/generator.jl` regenerates `src/LibPhreeqcRM.jl` with no diff on a fresh run.

TestItems suites (TDD acceptance):

4. `julia --project=PhreeqcRM -e 'using TestItemRunner; @run_package_tests filter = ti -> !(:perf in ti.tags || :threads in ti.tags || :bench in ti.tags)'` — default `:fast` set passes (lifecycle, errors, concentrations shape + round-trip, Aqua).
5. `julia --project=PhreeqcRM -e 'using TestItemRunner; @run_package_tests filter = ti -> :perf in ti.tags'` — every hot-path operation (`set_concentrations!`, `get_concentrations!`, `run_cells!`, full step!) reports `@allocated == 0` after warmup.
6. `julia -t auto --project=PhreeqcRM -e 'using TestItemRunner; @run_package_tests filter = ti -> :threads in ti.tags'` — OMP thread count is honored, two instances driven from two Julia threads produce results equal (to `rtol = 1e-10`) to the serial baseline, oversubscription warning fires when `Threads.nthreads() × nthreads > Sys.CPU_THREADS`.
7. `julia --project=PhreeqcRM -e 'using TestItemRunner; @run_package_tests filter = ti -> :integration in ti.tags'` — `examples/advection_reaction.jl` reproduces the upstream `advect.pqi` reference to `rtol = 1e-8`.

Reference suite (three-way pipeline):

8. `(cd PhreeqcRM/test/c_build && make)` compiles every `driver.c` against `libphreeqcrm`. No errors; one driver binary per case.
9. `julia --project=PhreeqcRM PhreeqcRM/test/reference_suite/regenerate.jl` (one-time, maintainer-only) populates `reference/phreeqc_cli.sel` and `reference/c_driver.sel` per case, asserting CLI ≡ C internally before writing.
10. `julia --project=PhreeqcRM -e 'using TestItemRunner; @run_package_tests filter = ti -> :integration in ti.tags'` — every reference case passes CLI ≡ C ≡ Julia at `rtol = 1e-8, atol = 1e-12`. `test/results.json` is written with per-case pass/fail + max error.

Benchmarks (CI-blocking + scheduled):

11. `julia --project=PhreeqcRM/benchmark PhreeqcRM/benchmark/time_c_drivers.jl` produces `c_timings.json` (per-case median C step time from 5 runs).
12. `julia --project=PhreeqcRM/benchmark PhreeqcRM/benchmark/runbench.jl --tier=full` produces `benchmark/latest.json`, `benchmark/judge_<julia-version>.json`, `benchmark/judge_summary.md`, and the full plot set under `benchmark/plots/`. Exit code is 0 iff no `:regression` leaf at `time_tolerance = 0.05, memory_tolerance = 0.0`. Wrapper-overhead ratio < 1.10 on every case; threading scan shows monotone speedup to core saturation.
13. PR Benchmark gate: the `Benchmark-Quick.yml` workflow runs on every pull request, exits non-zero on regression, and posts a markdown table + inline plots as a PR comment via `Benchmark-Comment.yml`.
14. Cross-version aggregation: `Benchmark-Full.yml` produces `plots/julia_versions.png` (grouped bars per case across Julia versions) and `plots/history/<case>.png` (time vs commit from `benchmark-history` branch).

Docs:

15. `julia --project=PhreeqcRM/docs PhreeqcRM/docs/make.jl` builds the site cleanly. Every exported function has a docstring (Documenter fails the build if not). `validation/results.md`, `validation/performance.md`, and the embedded plots all reflect the freshly-run suites.

CI:

16. GitHub Actions `CI.yml` runs `build-libphreeqcrm` → `test` (matrix: 3 OS × 3 Julia versions × {1, 4} threads) → `aqua` → `format` → `docs`. All green on `main`. Codecov reports ≥ 80% line coverage of `src/`.
17. `Benchmark-Quick.yml` runs on every PR and fails the workflow on > 5% regression or any new hot-loop allocation.
18. `Benchmark-Full.yml` runs on every `main` push + tag, appends to `benchmark-history` branch, opens an issue automatically on regression.
19. `Benchmark-Comment.yml` posts an up-to-date summary comment to the PR with the judge table and key plots inlined.

JLL-swap dry run:

20. Replace the env-var resolution in `PhreeqcRM_jll/src/PhreeqcRM_jll.jl` with a hard-coded path (or, when ready, `using PhreeqcRM_jll; const libphreeqcrm = PhreeqcRM_jll.libphreeqcrm`). Re-run suite #4. `PhreeqcRM.jl` source untouched. Proves the split achieves zero-code-change Yggdrasil migration.

## Known gotchas baked into the design

- `nthreads=1` default prevents OpenMP × Julia thread oversubscription. Constructor warns if `Threads.nthreads() * nthreads > Sys.CPU_THREADS`.
- Driving one `PhreeqcRMInstance` from multiple Julia threads at once is undefined behavior; multiple instances may be driven concurrently. No internal lock — pay for what you use.
- Concentration matrix is `(nxyz, ncomps)`, **not** `(nxyz, ncomps)` — `zeros_concentrations(rm)` enforces this; shape validation in setters prevents silent scrambling.
- `OpenFiles` is opt-in via `open_output!`; constructor creates no files.
- `close` is the primary teardown; finalizer is a safety net only (no `ccall` storms at GC time while OpenMP threads are live).
- `SetComponentH2O` is called in the constructor (must precede `LoadDatabase`).
- `set_units!` requires `solution` explicitly — silently defaulting it would silently change the meaning of every concentration passed to `set_concentrations!`.
- `find_components!` is required before any concentration op; asserted at runtime.
- `run_cells!` asserts `SetTime` and `SetTimeStep` were called (otherwise PhreeqcRM silently uses 0).
- All generated `@ccall`s go through `PhreeqcRM_jll.libphreeqcrm`; swapping to the real JLL is a `Pkg.rm` + `Pkg.add` away.
- macOS dylib uses `@loader_path` rpath so the binary is relocatable inside the repo.
