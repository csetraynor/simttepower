test_that("analysis_coxph() returns per-term named numerics", {
    skip_if_not_installed("survival")
    set.seed(1)
    events <- .two_arm_events()
    out <- analysis_coxph(events)
    expect_true(all(c("estimate_armexperimental", "se_armexperimental",
        "p_armexperimental", "hr_armexperimental", "hr_lo_armexperimental",
        "hr_hi_armexperimental", "converged") %in% names(out)))
    expect_identical(unname(out["converged"]), 1)
})

test_that("analysis_coxph() takes a custom formula (regimen/dose/covariate contrasts)", {
    skip_if_not_installed("survival")
    set.seed(2)
    events <- .two_arm_events()
    events$age <- stats::rnorm(nrow(events), 50, 10)
    out <- analysis_coxph(events, formula = ~ arm + age)
    expect_true("estimate_age" %in% names(out))
    expect_true("estimate_armexperimental" %in% names(out))
})

test_that("analysis_coxph() rejects a two-sided formula", {
    skip_if_not_installed("survival")
    events <- .two_arm_events()
    expect_error(analysis_coxph(events, formula = sim_time ~ arm),
        "one-sided")
})

test_that("analysis_coxph() reports a fit failure as converged = 0, not an error", {
    skip_if_not_installed("survival")
    events <- .two_arm_events()
    out <- analysis_coxph(events, formula = ~does_not_exist)
    expect_identical(unname(out["converged"]), 0)
    expect_identical(length(out), 1L)  # no per-term columns when the fit failed
})

test_that("analysis_logrank() returns a p-value", {
    skip_if_not_installed("survival")
    set.seed(3)
    events <- .two_arm_events()
    out <- analysis_logrank(events)
    expect_true(is.numeric(out[["p"]]))
    expect_true(out[["p"]] >= 0 && out[["p"]] <= 1)
    expect_identical(unname(out["converged"]), 1)
})

test_that("analysis_logrank() takes a `group` column other than arm", {
    skip_if_not_installed("survival")
    events <- .two_arm_events()
    events$regimen <- events$arm
    out <- analysis_logrank(events, group = "regimen")
    expect_true(is.numeric(out[["p"]]))
})
