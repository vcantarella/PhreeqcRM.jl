# Top-level test entry point. Each test lives in its own @testitem block
# in test/test_*.jl files; TestItemRunner picks them up.
#
# Run subsets by tag:
#   julia --project=PhreeqcRM -e 'using TestItemRunner; \
#       @run_package_tests filter = ti -> !(:perf in ti.tags || :threads in ti.tags)'

using TestItemRunner

# Default behaviour: run everything that isn't a benchmark smoke test.
@run_package_tests filter = ti -> !(:bench in ti.tags)
