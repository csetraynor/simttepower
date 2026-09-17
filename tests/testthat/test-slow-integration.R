# Heavier end-to-end checks: real dosing regimen + real covariate
# distribution + a custom formula + direction-aware rejection, all
# together, at a larger n_sims. Gated behind SIMTTEPOWER_SLOW_TESTS (see
# dev/run-tests.R --check, which sets it) -- the fast suite already
# covers each piece individually and stays fast without this file.
test_that("a full scenario (dosing regimen x covariates x direction-aware reject) runs end to end", {
    skip_if_not_slow()
    skip_if_not_installed("survival")

    p <- .test_param()
    cov <- data.frame(ID = 1:25, time = 0, age = stats::rnorm(25, 55, 8))
    ev_q4w <- data.frame(ID = 1:25, time = 0, amt = 400, cmt = 1, evid = 1,
        ii = 4, addl = 5)
    ev_qw <- data.frame(ID = 1:25, time = 0, amt = 100, cmt = 1, evid = 1,
        ii = 1, addl = 23)

    comparator <- arm(label = "comparator", n = 25, model = "irm1_hazard",
        end = 24, param = p, covariates = cov, beta = c(age = 0.01),
        data = ev_qw, regimen = "qw")
    experimental <- arm(label = "experimental", n = 25, model = "irm1_hazard",
        end = 24, param = p, covariates = cov, beta = c(age = 0.01),
        data = ev_q4w, regimen = "q4w_loading")

    design <- trial_design(
        arms = list(comparator, experimental),
        analyses = list(
            coxph_adj = function(events) {
                analysis_coxph(events, formula = ~ arm + age)
            },
            logrank = analysis_logrank
        )
    )

    grid <- scenario_grid(design, over = list(arm = "experimental",
        field = "param.IC50", values = c(1, 4)),
        truth = function(v) c(estimate_armexperimental = -0.2 * (v$IC50 - 1)))

    # Regression guard for the simtte lp/data merge bug this test itself
    # first surfaced (60 "Parameter column lp must not contain missing
    # values" warnings from combining covariates+beta with a custom
    # dosing `data` on the same arm -- reports/03_phase1_report.md
    # section 6 risk 1, fixed in simtte per
    # ../simtte/reports/29_simttepower_feedback_lp_merge.md and NOT a
    # cosmetic issue: it silently reclassified real events as
    # administrative censoring). Fails loudly if the warning ever comes
    # back, e.g. from a simtte downgrade.
    res <- testthat::expect_no_warning(
        power_sim(grid, n_sims = 15, seed = 99, reject = reject_direction,
            progress = FALSE)
    )
    expect_identical(nrow(res$results), 2L * 15L * 2L)
    expect_true(all(c("estimate_age", "estimate_armexperimental") %in%
        names(res$results)))

    s <- summary(res)
    expect_identical(nrow(s), 2L * 2L)
    expect_true(all(s$reject_rate >= 0 & s$reject_rate <= 1))
    # The IC50 = 1 scenario has zero true log-HR (comparator == experimental
    # dose-response) -- direction-aware rejection there should be rare.
    expect_true(s$reject_rate[s$IC50 == 1][1] <= 0.3)
})

test_that("power_sim() reproducibility holds at a larger n_sims/grid", {
    skip_if_not_slow()
    g <- scenario_grid(.test_design(), over = list(
        list(arm = "experimental", field = "param.IC50", values = c(1, 2, 4)),
        list(arm = NULL, field = "end", values = c(12, 24))
    ))
    r1 <- power_sim(g, n_sims = 20, seed = 2024, progress = FALSE)
    r2 <- power_sim(g, n_sims = 20, seed = 2024, progress = FALSE)
    cols <- setdiff(names(r1$results), "runtime_sec")
    expect_identical(r1$results[cols], r2$results[cols])
})
