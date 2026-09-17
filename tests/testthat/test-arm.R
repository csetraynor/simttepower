test_that("arm() builds a valid object with defaults", {
    a <- .test_arm("comparator")
    expect_s3_class(a, "simttepower_arm")
    expect_identical(a$label, "comparator")
    expect_identical(a$regimen, "comparator")  # defaults to label
    expect_null(a$dose)
    expect_identical(a$n, 10L)
    expect_null(a$delta)  # unset: falls through to sim_tte_ode()'s own default
    expect_identical(a$param, .test_param())
})

test_that("arm() regimen/dose are independent of label", {
    a <- .test_arm("armA", regimen = "q4w_then_qw", dose = 100)
    expect_identical(a$regimen, "q4w_then_qw")
    expect_identical(a$dose, 100)
})

test_that("arm() validates label", {
    expect_error(arm(label = 1, n = 10, model = "irm1_hazard"), "label")
    expect_error(arm(label = "", n = 10, model = "irm1_hazard"), "label")
    expect_error(arm(label = c("a", "b"), n = 10, model = "irm1_hazard"),
        "label")
})

test_that("arm() validates n", {
    expect_error(.test_arm("a", n = 0), "positive whole number")
    expect_error(.test_arm("a", n = -5), "positive whole number")
    expect_error(.test_arm("a", n = 2.5), "positive whole number")
})

test_that("arm() validates model", {
    expect_error(arm(label = "a", n = 10, model = "not_a_model"),
        "not one of simtte's built-in models")
    expect_error(arm(label = "a", n = 10, model = 42), "must be a")
})

test_that("arm() rejects `seed` -- assigned by the engine, not the caller", {
    expect_error(arm(label = "a", n = 10, model = "irm1_hazard", seed = 1),
        "assigned per replicate")
})

test_that("arm() rejects unknown arguments", {
    expect_error(arm(label = "a", n = 10, model = "irm1_hazard", bogus = 1),
        "Unknown argument")
})

test_that("arm() validates dose/regimen shape", {
    expect_error(.test_arm("a", dose = c(1, 2)), "dose")
    expect_error(.test_arm("a", regimen = 1), "regimen")
})

test_that("print.simttepower_arm() runs without error", {
    expect_output(print(.test_arm("comparator")), "simttepower_arm")
})
