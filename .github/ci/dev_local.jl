using Pkg

# The local PhreeqcRM_jll/ stub and the main PhreeqcRM package both share names
# with different packages in the General registry (different UUIDs), so
# Pkg.instantiate cannot resolve either of them via the registry. Dev whichever
# of the two are listed as deps of the active env in a single call, so Pkg sees
# both UUID->path mappings before doing any registry-backed resolution, then
# instantiate.
root = abspath(joinpath(@__DIR__, "..", ".."))
stub = joinpath(root, "PhreeqcRM_jll")

specs = PackageSpec[]
deps = Pkg.project().dependencies
haskey(deps, "PhreeqcRM_jll") && push!(specs, PackageSpec(path=stub))
haskey(deps, "PhreeqcRM")     && push!(specs, PackageSpec(path=root))
isempty(specs) || Pkg.develop(specs)

Pkg.instantiate()
