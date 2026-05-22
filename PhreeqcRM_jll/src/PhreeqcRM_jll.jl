"""
    PhreeqcRM_jll

Local stub mimicking the public surface that a Yggdrasil-built `PhreeqcRM_jll`
would expose. Resolves `libphreeqcrm` from `ENV["JULIA_PHREEQCRM_PATH"]` so the
wrapper package `PhreeqcRM.jl` can depend on `PhreeqcRM_jll` today and stay
unchanged when the official JLL ships.

When the real JLL is published, swap this package for the registered one — no
source changes required in `PhreeqcRM.jl`.
"""
module PhreeqcRM_jll

using Libdl

const libphreeqcrm = let
    p = get(ENV, "JULIA_PHREEQCRM_PATH", "")
    if isempty(p)
        error("""
        PhreeqcRM_jll (local stub): JULIA_PHREEQCRM_PATH is not set.

        Build libphreeqcrm locally with:
            bash deps/build_phreeqcrm.sh
        Then export:
            export JULIA_PHREEQCRM_PATH="\$PWD/deps/usr/lib/libPhreeqcRM.dylib"
        and restart Julia.
        See deps/README.md.
        """)
    end
    isfile(p) || error("PhreeqcRM_jll: JULIA_PHREEQCRM_PATH=$p does not exist.")
    p
end

const PATH    = dirname(libphreeqcrm)
const LIBPATH = PATH

export libphreeqcrm

end # module
