using Pkg

# The local PhreeqcRM_jll/ stub and the main PhreeqcRM package both share
# names with different packages in the General registry (different UUIDs).
# Dev both by path so Pkg never resolves either name via the registry.
# The stub is dev'd even when it's not a direct dep of the active env,
# because every env that depends on PhreeqcRM transitively needs it.
root = abspath(joinpath(@__DIR__, "..", ".."))
stub = joinpath(root, "PhreeqcRM_jll")

specs = [PackageSpec(path=stub)]
Pkg.project().name == "PhreeqcRM" || push!(specs, PackageSpec(path=root))
Pkg.develop(specs)

Pkg.instantiate()
