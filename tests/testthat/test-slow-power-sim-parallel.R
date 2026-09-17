# Phase 2 slow tests: real PSOCK/fork worker dispatch. Gated behind
# SIMTTEPOWER_SLOW_TESTS (see dev/run-tests.R --check). Never more than
# 2 workers (CRAN policy). These need simttepower actually installed
# (not just devtools::load_all()ed), since a PSOCK worker's own
# library(simttepower) call resolves against the installed library path
# -- `dev/run-tests.R --check` builds/installs the package before
# running tests, so this is only a concern for a manual, un-installed
# devtools::load_all() session; noted, not worked around here.

.results_excl_runtime <- function(res) {
    cols <- setdiff(names(res$results), "runtime_sec")
    ord <- intersect(c("scenario_id", names(res$grid), "replicate", "analysis"),
        cols)
    ord <- unique(ord)
    d <- res$results[cols]
    d <- d[do.call(order, d[ord]), ]
    rownames(d) <- NULL
    d
}

test_that("workers = 1 and workers = 2 (PSOCK) give byte-identical results", {
    skip_if_not_slow()
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1, 3)))
    r1 <- power_sim(g, n_sims = 4, seed = 42, progress = FALSE, workers = 1)
    r2 <- power_sim(g, n_sims = 4, seed = 42, progress = FALSE, workers = 2,
        parallel = "psock")
    expect_identical(.results_excl_runtime(r1), .results_excl_runtime(r2))
})

test_that("workers = 1 and workers = 2 (fork) give byte-identical results", {
    skip_if_not_slow()
    skip_on_os("windows")
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1, 3)))
    r1 <- power_sim(g, n_sims = 4, seed = 42, progress = FALSE, workers = 1)
    r3 <- power_sim(g, n_sims = 4, seed = 42, progress = FALSE, workers = 2,
        parallel = "fork")
    expect_identical(.results_excl_runtime(r1), .results_excl_runtime(r3))
})

test_that("parallel = \"fork\" errors clearly on Windows", {
    skip_if_not_slow()
    skip_on_os(c("mac", "linux", "solaris"))  # only meaningful to run on Windows
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    expect_error(
        power_sim(g, n_sims = 1, seed = 1, workers = 2, parallel = "fork"),
        "not supported on Windows"
    )
})

test_that("the ambient RNG state/kind is restored after parallel dispatch", {
    skip_if_not_slow()
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))

    set.seed(321)
    before <- .Random.seed
    before_kind <- RNGkind()
    invisible(power_sim(g, n_sims = 2, seed = 1, progress = FALSE,
        workers = 2, parallel = "psock"))
    expect_identical(.Random.seed, before)
    expect_identical(RNGkind(), before_kind)

    set.seed(321)
    before <- .Random.seed
    invisible(power_sim(g, n_sims = 2, seed = 1, progress = FALSE,
        workers = 2, parallel = "fork"))
    expect_identical(.Random.seed, before)
})

test_that("a tte_model() arm's prepared object broadcasts correctly to PSOCK workers", {
    skip_if_not_slow()
    my_code <- paste(
        "$PARAM CL=2, V2=20, KA=1",
        "$CMT GUT CENT",
        "$ODE",
        "dxdt_GUT = -KA*GUT;",
        "dxdt_CENT = KA*GUT - (CL/V2)*CENT;",
        sep = "\n"
    )
    tm <- simtte::tte_model(model = my_code, hazard = "H0",
        params = list(H0 = 0.1))
    a1 <- arm(label = "comparator", n = 15, model = tm, end = 10,
        param = list(H0 = 0.1))
    a2 <- arm(label = "experimental", n = 15, model = tm, end = 10,
        param = list(H0 = 0.3))
    design <- trial_design(arms = list(a1, a2),
        analyses = list(coxph = analysis_coxph))
    g <- scenario_grid(design, over = list(arm = "experimental",
        field = "param.H0", values = c(0.3, 0.5)))

    r1 <- power_sim(g, n_sims = 3, seed = 11, progress = FALSE, workers = 1)
    r2 <- power_sim(g, n_sims = 3, seed = 11, progress = FALSE, workers = 2,
        parallel = "psock")
    expect_identical(.results_excl_runtime(r1), .results_excl_runtime(r2))
    expect_true(all(r2$results$converged == 1))
})

test_that("a captured replicate error on a worker matches the sequential path", {
    skip_if_not_slow()
    d <- .test_design()
    d$end <- NULL
    d$arms <- lapply(d$arms, function(a) { a$end <- NULL; a })
    g <- scenario_grid(d, over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))

    r_seq <- power_sim(g, n_sims = 2, seed = 1, progress = FALSE, workers = 1)
    r_par <- power_sim(g, n_sims = 2, seed = 1, progress = FALSE, workers = 2,
        parallel = "psock")
    expect_true(all(!is.na(r_par$results$error)))
    expect_identical(r_seq$results$error, r_par$results$error)
})

# The two former "broken worker task" tests (one per parallel = mode)
# moved to test-power-sim-parallel.R and merged into one fast test: since
# .prepare_models() now runs in the parent before any cluster/fork is
# created, a broken model fails at the same pre-flight step regardless
# of `parallel =`, before any real worker ever spawns -- see that test
# for why this is no longer slow-only.

test_that("12 fresh-cache PSOCK runs of a tte_model() arm succeed, with no retry anywhere", {
    skip_if_not_slow()
    # Phase 2's own version of this loop needed up to 3 loadso() retries
    # to reach 0/12 failures (reports/05_phase2_report.md). This rework
    # has no retry left anywhere in simttepower's own code -- the
    # replacement is simtte::simtte_prepare_model(), which simtte's own
    # investigation found race-free by construction (never a worker
    # rebuild to race on -- see
    # ../simtte/reports/30_simttepower_feedback_worker_loading.md). A
    # fresh options(simtte.cache_dir = ) per run rules out any leftover
    # artifact from a previous run/session masking a real race.
    my_code <- paste(
        "$PARAM CL=2, V2=20, KA=1",
        "$CMT GUT CENT",
        "$ODE",
        "dxdt_GUT = -KA*GUT;",
        "dxdt_CENT = KA*GUT - (CL/V2)*CENT;",
        sep = "\n"
    )
    old_cache_dir <- getOption("simtte.cache_dir")
    on.exit(options(simtte.cache_dir = old_cache_dir), add = TRUE)

    for (i in 1:12) {
        fresh_dir <- file.path(tempdir(), paste0("simttepower-stress-", i))
        dir.create(fresh_dir, showWarnings = FALSE)
        options(simtte.cache_dir = fresh_dir)

        tm <- simtte::tte_model(model = my_code, hazard = "H0",
            params = list(H0 = 0.1))
        a1 <- arm(label = "comparator", n = 10, model = tm, end = 10,
            param = list(H0 = 0.1))
        a2 <- arm(label = "experimental", n = 10, model = tm, end = 10,
            param = list(H0 = 0.3))
        design <- trial_design(arms = list(a1, a2),
            analyses = list(coxph = analysis_coxph))
        g <- scenario_grid(design, over = list(arm = "experimental",
            field = "param.H0", values = c(0.3)))

        res <- power_sim(g, n_sims = 2, seed = i, progress = FALSE,
            workers = 2, parallel = "psock")
        expect_true(all(is.na(res$results$error)),
            info = paste("run", i, "errors:",
                paste(unique(res$results$error), collapse = "; ")))
    }
})
