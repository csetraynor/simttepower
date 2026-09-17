# Mirrors simtte's own tests/testthat/helper-ode-models.R skip_if_not_slow():
# `R CMD check`/CI runs the slow set (SIMTTEPOWER_SLOW_TESTS=true is set by
# dev/run-tests.R --check without --fast); interactive/targeted runs
# default to fast.
skip_if_not_slow <- function() {
    if (!identical(Sys.getenv("SIMTTEPOWER_SLOW_TESTS"), "true")) {
        testthat::skip("slow test (set SIMTTEPOWER_SLOW_TESTS=true to run)")
    }
}
