test_that("reject_default() uses a plain 'p' column when present", {
    expect_true(reject_default(list(p = 0.01), alpha = 0.05))
    expect_false(reject_default(list(p = 0.5), alpha = 0.05))
    expect_false(reject_default(list(p = NA_real_), alpha = 0.05))
})

test_that("reject_default() auto-detects a single p_* column", {
    row <- list(p_armexperimental = 0.01, converged = 1)
    expect_true(reject_default(row))
    row2 <- list(p_armexperimental = 0.5, converged = 1)
    expect_false(reject_default(row2))
})

test_that("reject_default() errors on an ambiguous p_* column set", {
    row <- list(p_armlow = 0.01, p_armhigh = 0.2)
    expect_error(reject_default(row), "Cannot auto-detect")
    expect_true(reject_default(row, p_col = "p_armlow"))
})

test_that("reject_direction() requires both a small p and the right sign", {
    truth <- c(estimate_armexperimental = -0.5)
    right_sign <- list(p_armexperimental = 0.01,
        estimate_armexperimental = -0.3)
    wrong_sign <- list(p_armexperimental = 0.01,
        estimate_armexperimental = 0.3)
    big_p <- list(p_armexperimental = 0.5, estimate_armexperimental = -0.3)

    expect_true(reject_direction(right_sign, truth = truth))
    expect_false(reject_direction(wrong_sign, truth = truth))
    expect_false(reject_direction(big_p, truth = truth))
})

test_that("reject_direction() is FALSE, not an error, with no truth", {
    row <- list(p_armexperimental = 0.01, estimate_armexperimental = -0.3)
    expect_false(reject_direction(row, truth = NULL))
})
