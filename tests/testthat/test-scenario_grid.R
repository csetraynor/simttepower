test_that("scenario_grid() crosses a single factor", {
    d <- .test_design()
    g <- scenario_grid(d, over = list(arm = "experimental",
        field = "param.IC50", values = c(1, 2, 4)))
    expect_s3_class(g, "simttepower_scenario_grid")
    expect_identical(nrow(g), 3L)
    expect_identical(g$IC50, c(1, 2, 4))
    expect_identical(g$scenario_id, c("s1", "s2", "s3"))
    expect_true(all(vapply(g$scenario,
        function(s) inherits(s, "simttepower_scenario"), logical(1))))
})

test_that("a varied param and a varied formula beta go through the same path", {
    # same set_field() mechanism either way -- both just resolve a
    # one- or two-segment dotted path (reports/01_phase1_plan.md section 2)
    d <- .test_design()
    g_param <- scenario_grid(d, over = list(arm = "experimental",
        field = "param.CL", values = c(1, 2)))
    expect_identical(g_param$CL, c(1, 2))
    expect_identical(g_param$scenario[[1]]$design$arms[[2]]$param$CL, 1)
    expect_identical(g_param$scenario[[2]]$design$arms[[2]]$param$CL, 2)

    a1 <- .test_arm("comparator")
    a2 <- .test_arm("experimental", beta = c(age = 0))
    d2 <- trial_design(arms = list(a1, a2), analyses = list(coxph = analysis_coxph))
    g_beta <- scenario_grid(d2, over = list(arm = "experimental",
        field = "beta.age", values = c(0, 0.5)))
    expect_identical(g_beta$age, c(0, 0.5))
    expect_identical(g_beta$scenario[[2]]$design$arms[[2]]$beta[["age"]], 0.5)
})

test_that("scenario_grid() crosses multiple factors", {
    d <- .test_design()
    g <- scenario_grid(d, over = list(
        list(arm = "experimental", field = "param.IC50", values = c(1, 2)),
        list(arm = NULL, field = "end", values = c(12, 24))
    ))
    expect_identical(nrow(g), 4L)
    expect_setequal(g$IC50, c(1, 2))
    expect_setequal(g$end, c(12, 24))
})

test_that("scenario_grid() supports list-valued factors (e.g. dosing data)", {
    d <- trial_design(arms = list(.test_arm("armA")),
        analyses = list(coxph = analysis_coxph))
    ev1 <- data.frame(ID = 1:10, time = 0, amt = 100, cmt = 1, evid = 1)
    ev2 <- data.frame(ID = 1:10, time = 0, amt = 200, cmt = 1, evid = 1)
    g <- scenario_grid(d, over = list(arm = "armA", field = "data",
        values = list(ev1, ev2)))
    expect_identical(nrow(g), 2L)
    expect_true(is.list(g$data))
    expect_identical(g$scenario[[1]]$design$arms[[1]]$data, ev1)
    expect_identical(g$scenario[[2]]$design$arms[[1]]$data, ev2)
})

test_that("scenario_grid() reads a `truth` function of the varied values", {
    d <- .test_design()
    g <- scenario_grid(d, over = list(arm = "experimental",
        field = "param.IC50", values = c(1, 2)),
        truth = function(v) c(estimate_armexperimental = -v$IC50 / 10))
    expect_identical(g$scenario[[1]]$truth,
        c(estimate_armexperimental = -0.1))
    expect_identical(g$scenario[[2]]$truth,
        c(estimate_armexperimental = -0.2))
})

test_that("scenario_grid() reads a `truth` list, one entry per scenario", {
    d <- .test_design()
    truths <- list(c(estimate_armexperimental = -0.1),
        c(estimate_armexperimental = -0.2))
    g <- scenario_grid(d, over = list(arm = "experimental",
        field = "param.IC50", values = c(1, 2)), truth = truths)
    expect_identical(g$scenario[[1]]$truth, truths[[1]])
    expect_identical(g$scenario[[2]]$truth, truths[[2]])
})

test_that("scenario_grid() validates field paths eagerly", {
    d <- .test_design()
    expect_error(
        scenario_grid(d, over = list(arm = "nope", field = "n", values = 1)),
        "no arm labeled"
    )
    expect_error(
        scenario_grid(d, over = list(arm = NULL, field = "bogus", values = 1)),
        "field = \"end\""
    )
    expect_error(
        scenario_grid(d, over = list(arm = "experimental",
            field = "a.b.c", values = 1)),
        "at most two"
    )
})

test_that("scenario_grid() catches duplicate factor column names", {
    d <- .test_design()
    expect_error(
        scenario_grid(d, over = list(
            list(arm = "experimental", field = "param.CL", values = 1),
            list(arm = "experimental", field = "param.V2", values = 1,
                name = "CL")
        )),
        "duplicate factor column"
    )
})

test_that("scenario_grid() rejects a truth list of the wrong length", {
    d <- .test_design()
    expect_error(
        scenario_grid(d, over = list(arm = "experimental",
            field = "param.IC50", values = c(1, 2)),
            truth = list(c(estimate_armexperimental = -0.1))),
        "truth"
    )
})

test_that("print.simttepower_scenario_grid() runs without error, even with list columns", {
    d <- trial_design(arms = list(.test_arm("armA")),
        analyses = list(coxph = analysis_coxph))
    ev1 <- data.frame(ID = 1:10, time = 0, amt = 100, cmt = 1, evid = 1)
    ev2 <- data.frame(ID = 1:10, time = 0, amt = 200, cmt = 1, evid = 1)
    g <- scenario_grid(d, over = list(arm = "armA", field = "data",
        values = list(ev1, ev2)))
    expect_output(print(g), "scenario_grid")
    expect_output(print(g), "<data.frame>")
})
