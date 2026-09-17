test_that("trial_design() builds a valid object", {
    d <- .test_design()
    expect_s3_class(d, "simttepower_trial_design")
    expect_length(d$arms, 2)
    expect_identical(names(d$analyses), "coxph")
})

test_that("trial_design() allows a single-arm design", {
    d <- trial_design(arms = list(.test_arm("only")),
        analyses = list(coxph = analysis_coxph))
    expect_length(d$arms, 1)
})

test_that("trial_design() rejects duplicate arm labels", {
    expect_error(
        trial_design(arms = list(.test_arm("dup"), .test_arm("dup")),
            analyses = list(coxph = analysis_coxph)),
        "unique"
    )
})

test_that("trial_design() rejects empty/malformed arms and analyses", {
    expect_error(trial_design(arms = list(), analyses = list(coxph = analysis_coxph)),
        "arms")
    expect_error(trial_design(arms = list(.test_arm("a")), analyses = list()),
        "analyses")
    expect_error(
        trial_design(arms = list(.test_arm("a")), analyses = list(1)),
        "analyses"
    )
})

test_that("trial_design() validates `end`", {
    expect_error(
        trial_design(arms = list(.test_arm("a")),
            analyses = list(coxph = analysis_coxph), end = "twelve"),
        "end"
    )
})

test_that("print.simttepower_trial_design() runs without error", {
    expect_output(print(.test_design()), "simttepower_trial_design")
})
