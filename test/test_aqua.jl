using TestItems

@testitem "Aqua quality checks" begin
    using Aqua, PhreeqcRM
    # ambiguities = false: a couple come from upstream Base/Statistics interactions,
    # not from our code; we'll narrow these once the API is stable.
    # stale_deps: PhreeqcRM_jll is referenced only through @ccall string-name
    # resolution that Aqua's static analysis doesn't see — explicitly mark it
    # as a known consumer.
    Aqua.test_all(PhreeqcRM;
                  ambiguities = false,
                  piracies = (broken = false,),
                  stale_deps = (ignore = [:PhreeqcRM_jll],))
end
