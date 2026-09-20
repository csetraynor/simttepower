# Phase 2: power_sim(workers = , cluster = , parallel = ). Fast tests here
# are argument validation and cluster lifecycle only, no PSOCK/fork
# dispatch (that needs real worker processes -- slow, below). Never more
# than 2 workers anywhere (CRAN policy, .claude/CLAUDE.md).

test_that("workers = 1 (default) needs no parallel package machinery", {
    expect_identical(formals(power_sim)$workers, 1)
})

test_that("power_sim() validates workers/cluster/parallel", {
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    expect_error(power_sim(g, n_sims = 1, seed = 1, workers = 0),
        "positive whole number")
    expect_error(power_sim(g, n_sims = 1, seed = 1, workers = 1.5),
        "positive whole number")
    expect_error(power_sim(g, n_sims = 1, seed = 1, cluster = "not a cluster"),
        "cluster object")
    expect_error(power_sim(g, n_sims = 1, seed = 1, parallel = "bogus"))
})

test_that("a caller-supplied cluster is used as-is and never stopped", {
    skip_on_cran()
    cl <- parallel::makePSOCKcluster(2)
    on.exit(parallel::stopCluster(cl), add = TRUE)

    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    res <- power_sim(g, n_sims = 2, seed = 1, progress = FALSE, cluster = cl)
    expect_s3_class(res, "simttepower_result")
    # Still alive: a dead/stopped cluster errors on this call.
    expect_identical(unlist(parallel::clusterEvalQ(cl, 1 + 1)), c(2, 2))
})

test_that("an explicit `workers` is ignored (with a message) when `cluster` is given", {
    skip_on_cran()
    cl <- parallel::makePSOCKcluster(2)
    on.exit(parallel::stopCluster(cl), add = TRUE)

    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    expect_message(
        power_sim(g, n_sims = 1, seed = 1, progress = FALSE, cluster = cl,
            workers = 5),
        "ignored"
    )
})

test_that("a broken model in the grid fails pre-flight, before any worker spawns", {
    # .prepare_models() (R/power_sim.R) runs in the parent process before
    # .run_tasks_parallel() branches into fork/PSOCK at all -- a model
    # that cannot build therefore fails the same way, with the same
    # message, regardless of `parallel =`, and no real worker process is
    # ever created (so this needs neither skip_on_cran() nor a real
    # cluster/fork -- a behaviour change from Phase 2's own two,
    # dispatch-mode-specific, slow "dispatch failed" tests, replaced by
    # this one; reports/06_phase2b_report.md).
    broken <- structure(
        list(code = "$THIS_IS_NOT_A_VALID_MRGSOLVE_BLOCK", mod = NULL,
            hazard = "H0", hazard_params = list(H0 = 0.1), bsv_targets = NULL,
            name = "simttepower_test_broken_model", source = "text"),
        class = "simtte_model"
    )
    a1 <- arm(label = "comparator", n = 5, model = broken, end = 10,
        param = list(H0 = 0.1))
    a2 <- arm(label = "experimental", n = 5, model = broken, end = 10,
        param = list(H0 = 0.2))
    design <- trial_design(arms = list(a1, a2),
        analyses = list(coxph = analysis_coxph))
    g <- scenario_grid(design, over = list(arm = "experimental",
        field = "param.H0", values = c(0.2)))

    # mrgsolve's own parser also warns ("invalid blocks found: ...")
    # before it errors on this deliberately-broken model -- suppressed
    # here since it is the expected side effect of this test's own
    # garbage input, not a package warning worth surfacing.
    for (mode in c("psock", "fork")) {
        if (identical(mode, "fork") && .Platform$OS.type != "unix") next
        expect_error(
            suppressWarnings(
                power_sim(g, n_sims = 1, seed = 1, progress = FALSE,
                    workers = 2, parallel = mode)
            ),
            "preparing model\\(s\\) failed"
        )
    }
})

test_that("power_sim() never leaves a global mrgsolve option changed", {
    skip_on_cran()
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    before <- list(project = getOption("mrgsolve.project"),
        soloc = getOption("mrgsolve.soloc"))

    invisible(power_sim(g, n_sims = 1, seed = 1, progress = FALSE, workers = 1))
    expect_identical(getOption("mrgsolve.project"), before$project)
    expect_identical(getOption("mrgsolve.soloc"), before$soloc)

    invisible(power_sim(g, n_sims = 2, seed = 1, progress = FALSE,
        workers = 2, parallel = "psock"))
    expect_identical(getOption("mrgsolve.project"), before$project)
    expect_identical(getOption("mrgsolve.soloc"), before$soloc)

    if (.Platform$OS.type == "unix") {
        invisible(power_sim(g, n_sims = 2, seed = 1, progress = FALSE,
            workers = 2, parallel = "fork"))
        expect_identical(getOption("mrgsolve.project"), before$project)
        expect_identical(getOption("mrgsolve.soloc"), before$soloc)
    }
})

test_that(".handle_worker_failures() turns a try-error placeholder into an error row", {
    # The one path a real test cannot exercise end-to-end without
    # actually killing a worker process (a genuine process death, e.g. a
    # segfault or kill signal -- see reports/06_phase2b_report.md).
    # Exercised directly here instead, with a stubbed try-error element,
    # per the same pattern .handle_worker_failures() itself expects from
    # mclapply().
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    task_table <- data.frame(scenario_row = 1L, replicate = 1L, global_index = 1L)
    cond <- simpleError("worker killed")
    stub <- structure("try-error placeholder", class = "try-error",
        condition = cond)
    rows <- simttepower:::.handle_worker_failures(list(stub), g, task_table)
    row <- rows[[1]]
    expect_true(all(grepl("worker process failed: worker killed", row$error)))
})
