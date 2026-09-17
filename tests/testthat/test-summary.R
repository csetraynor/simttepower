test_that("summary() returns one row per scenario x analysis", {
    g <- scenario_grid(.test_design(analyses = list(coxph = analysis_coxph,
        logrank = analysis_logrank)),
        over = list(arm = "experimental", field = "param.IC50", values = c(1, 3)))
    res <- power_sim(g, n_sims = 4, seed = 1, progress = FALSE)
    s <- summary(res)
    expect_s3_class(s, "simttepower_summary")
    expect_identical(nrow(s), 2L * 2L)
    expect_true(all(c("reject_rate", "reject_se", "n_sims", "n_errors",
        "median_runtime_sec") %in% names(s)))
    expect_true(all(s$reject_rate >= 0 & s$reject_rate <= 1))
})

test_that("summary()'s reject_se matches the binomial-proportion formula", {
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    res <- power_sim(g, n_sims = 6, seed = 1, progress = FALSE)
    s <- summary(res)
    p <- s$reject_rate[1]
    expect_equal(s$reject_se[1], sqrt(p * (1 - p) / s$n_sims[1]))
})

test_that("summary() reads a direction-aware reject rule with scenario truth", {
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(3)),
        truth = function(v) c(estimate_armexperimental = -0.2))
    res <- power_sim(g, n_sims = 5, seed = 1, reject = reject_direction,
        progress = FALSE)
    s <- summary(res)
    expect_true(s$reject_rate >= 0 && s$reject_rate <= 1)
    # A direction-aware rule can only reject a subset of what the default
    # (p < alpha alone) would -- sanity-check that ordering holds.
    res_default <- power_sim(g, n_sims = 5, seed = 1, progress = FALSE)
    expect_true(summary(res)$reject_rate <=
        summary(res_default)$reject_rate + 1e-9)
})

test_that("summary() forwards ... to the reject rule (e.g. p_col)", {
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    res <- power_sim(g, n_sims = 3, seed = 1, progress = FALSE)
    expect_error(summary(res), NA)  # single p_* column, no ambiguity here
    s <- summary(res, p_col = "p_armexperimental")
    expect_true(all(s$reject_rate >= 0 & s$reject_rate <= 1))
})

test_that("print.simttepower_summary() runs without error", {
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    res <- power_sim(g, n_sims = 2, seed = 1, progress = FALSE)
    expect_output(print(summary(res)), "simttepower_summary")
})
