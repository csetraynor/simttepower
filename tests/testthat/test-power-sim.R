test_that("power_sim() is reproducible for a fixed seed", {
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1, 3)))
    r1 <- power_sim(g, n_sims = 3, seed = 42, progress = FALSE)
    r2 <- power_sim(g, n_sims = 3, seed = 42, progress = FALSE)
    cols <- setdiff(names(r1$results), "runtime_sec")
    expect_identical(r1$results[cols], r2$results[cols])
})

test_that("power_sim() replicate k of scenario s does not depend on n_sims elsewhere", {
    # The global-index -> stream mapping is scenario-relative
    # ((scenario_row - 1) * n_sims + replicate), so this only holds
    # scenario-by-scenario, not across the whole grid -- documented
    # rectangular-grid limitation (reports/01_phase1_plan.md section 5).
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    r_small <- power_sim(g, n_sims = 2, seed = 7, progress = FALSE)
    r_big <- power_sim(g, n_sims = 5, seed = 7, progress = FALSE)
    cols <- setdiff(names(r_small$results), "runtime_sec")
    first_two_small <- r_small$results[r_small$results$replicate <= 2, cols]
    first_two_big <- r_big$results[r_big$results$replicate <= 2, cols]
    rownames(first_two_small) <- NULL
    rownames(first_two_big) <- NULL
    expect_identical(first_two_small, first_two_big)
})

test_that("power_sim() restores the ambient RNG state and kind", {
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    set.seed(123)
    before_seed <- .Random.seed
    before_kind <- RNGkind()
    invisible(power_sim(g, n_sims = 2, seed = 1, progress = FALSE))
    expect_identical(.Random.seed, before_seed)
    expect_identical(RNGkind(), before_kind)
})

test_that("power_sim() produces one row per scenario x replicate x analysis", {
    g <- scenario_grid(.test_design(analyses = list(coxph = analysis_coxph,
        logrank = analysis_logrank)),
        over = list(arm = "experimental", field = "param.IC50", values = c(1, 2)))
    res <- power_sim(g, n_sims = 3, seed = 1, progress = FALSE)
    expect_identical(nrow(res$results), 2L * 3L * 2L)
})

test_that("power_sim() attaches expected-events/duration columns", {
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    res <- power_sim(g, n_sims = 2, seed = 1, progress = FALSE)
    expect_true(all(c("n_events_comparator", "n_events_experimental",
        "duration") %in% names(res$results)))
})

test_that("power_sim() captures a per-replicate error without stopping", {
    d <- .test_design(analyses = list(coxph = analysis_coxph))
    d$end <- NULL
    d$arms <- lapply(d$arms, function(a) { a$end <- NULL; a })
    g <- scenario_grid(d, over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    res <- power_sim(g, n_sims = 2, seed = 1, progress = FALSE)
    expect_identical(nrow(res$results), 2L)
    expect_true(all(!is.na(res$results$error)))
    expect_true(all(grepl("no `end`", res$results$error)))
})

test_that("power_sim() validates its arguments", {
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    expect_error(power_sim("not a grid", n_sims = 1, seed = 1), "scenario_grid")
    expect_error(power_sim(g, n_sims = 0, seed = 1), "positive whole number")
    expect_error(power_sim(g, n_sims = 1, seed = "x"), "single number")
})

test_that("print.simttepower_result() runs without error", {
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    res <- power_sim(g, n_sims = 2, seed = 1, progress = FALSE)
    expect_output(print(res), "simttepower_result")
})
