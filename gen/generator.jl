# Regenerate src/LibPhreeqcRM.jl from the vendored C header.
#
# Run with:
#     julia --project=gen gen/generator.jl
#
# The generated file is committed — users do NOT regenerate on install.

using Clang.Generators

const HERE = @__DIR__
const HEADER_DIR = joinpath(HERE, "include")
const HEADER = joinpath(HEADER_DIR, "RM_interface_C.h")

isfile(HEADER) || error("Missing vendored header: $HEADER\n" *
                        "Copy from deps/usr/include/RM_interface_C.h after a successful Phase 0 build.")

# Use clang_args to point at the headers we vendored (RM_interface_C.h transitively
# includes IrmResult.h and irm_dll_export.h). No system header dependencies.
args = get_default_args()
push!(args, "-I" * HEADER_DIR)
push!(args, "-DIRM_DLL_EXPORT=")   # the export macro is a no-op for the generator

options = load_options(joinpath(HERE, "generator.toml"))

ctx = create_context([HEADER], args, options)
build!(ctx)

@info "Generated $(joinpath(HERE, "..", "src", "LibPhreeqcRM.jl"))"
