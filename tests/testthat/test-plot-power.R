# Phase 4: plot_power(). ggplot2 stays in Suggests -- every test here is
# guarded so the suite still passes cleanly without it installed.

.plot_summary <- function(n_values = c(1, 2, 4), color_field = NULL) {
    over <- list(list(arm = "experimental", field = "param.IC50",
        values = n_values))
    if (!is.null(color_field)) {
        over <- c(over, list(list(arm = "experimental", field = "n",
            values = c(10, 20))))
    }
    g <- scenario_grid(.test_design(), over = over)
    res <- power_sim(g, n_sims = 3, seed = 1, progress = FALSE)
    summary(res)
}

test_that("plot_power() errors clearly without ggplot2", {
    skip_if(requireNamespace("ggplot2", quietly = TRUE),
        "ggplot2 is installed -- this test only applies without it")
    s <- .plot_summary()
    expect_error(plot_power(s, x = "IC50"), "ggplot2")
})

test_that("plot_power() validates its input and column arguments", {
    skip_if_not_installed("ggplot2")
    s <- .plot_summary()
    expect_error(plot_power(data.frame(x = 1), x = "x"),
        "simttepower_summary")
    expect_error(plot_power(s, x = "not_a_column"), "not a column")
    expect_error(plot_power(s, x = "IC50", y = "not_a_column"),
        "not a column")
})

test_that("plot_power() returns a ggplot with the expected layers/mapping", {
    skip_if_not_installed("ggplot2")
    s <- .plot_summary()
    p <- plot_power(s, x = "IC50")
    expect_s3_class(p, "ggplot")
    layer_geoms <- vapply(p$layers, function(l) class(l$geom)[1], "")
    expect_true("GeomLine" %in% layer_geoms)
    expect_true("GeomPoint" %in% layer_geoms)
    expect_true("GeomRibbon" %in% layer_geoms)  # ci = TRUE by default

    # Black-box check of the x mapping: build the plot and confirm the
    # rendered x values match the summary's own IC50 column, rather than
    # relying on ggplot2's internal quosure representation.
    built <- ggplot2::ggplot_build(p)
    expect_setequal(built$data[[3]]$x, sort(unique(s$IC50)))
})

test_that("plot_power() handles a second factor (colour) and facet", {
    skip_if_not_installed("ggplot2")
    s <- .plot_summary(color_field = "n")
    p <- plot_power(s, x = "IC50", color = "n")
    expect_true("colour" %in% names(p$mapping) ||
        "colour" %in% names(p$layers[[1]]$mapping) ||
        "colour" %in% names(p$layers[[2]]$mapping))

    p2 <- plot_power(s, x = "IC50", facet = "n")
    expect_s3_class(p2$facet, "FacetWrap")
})

test_that("plot_power(ci = FALSE) skips the ribbon layer", {
    skip_if_not_installed("ggplot2")
    s <- .plot_summary()
    p <- plot_power(s, x = "IC50", ci = FALSE)
    layer_geoms <- vapply(p$layers, function(l) class(l$geom)[1], "")
    expect_false("GeomRibbon" %in% layer_geoms)
})

test_that("plot_power() skips the ribbon for a non-default y with no matching se", {
    skip_if_not_installed("ggplot2")
    s <- .plot_summary()
    p <- plot_power(s, x = "IC50", y = "median_runtime_sec")
    layer_geoms <- vapply(p$layers, function(l) class(l$geom)[1], "")
    expect_false("GeomRibbon" %in% layer_geoms)
})

test_that("plot_power() auto-pairs a <y>_se column by convention", {
    skip_if_not_installed("ggplot2")
    s <- .plot_summary()
    s$my_estimate <- s$reject_rate  # any numeric y
    s$my_estimate_se <- s$reject_se  # "<y>_se" convention
    p <- plot_power(s, x = "IC50", y = "my_estimate")
    layer_geoms <- vapply(p$layers, function(l) class(l$geom)[1], "")
    expect_true("GeomRibbon" %in% layer_geoms)
})

test_that("plot_power(se_col = ) overrides the auto-paired column", {
    skip_if_not_installed("ggplot2")
    s <- .plot_summary()
    # Synthetic, non-degenerate values: .plot_summary()'s own tiny grid
    # can give an exact reject_rate of 0 or 1 (reject_se = 0 either way),
    # which would make any se_col's ribbon identical regardless of its
    # actual value -- not what this test means to check.
    s$reject_rate <- seq(0.3, 0.7, length.out = nrow(s))
    s$reject_se <- 0.05
    s$other_se <- 0.2  # a deliberately different SE column
    p_auto <- plot_power(s, x = "IC50")
    p_override <- plot_power(s, x = "IC50", se_col = "other_se")
    built_auto <- ggplot2::ggplot_build(p_auto)
    built_override <- ggplot2::ggplot_build(p_override)
    # The ribbon layer is the 1st layer (geom_ribbon added before
    # geom_line()/geom_point()) -- its ymin/ymax should differ between
    # the two SE columns.
    expect_false(isTRUE(all.equal(built_auto$data[[1]]$ymin,
        built_override$data[[1]]$ymin)))
})

test_that("plot_power(se_col = ) errors clearly on an absent column", {
    skip_if_not_installed("ggplot2")
    s <- .plot_summary()
    expect_error(plot_power(s, x = "IC50", se_col = "not_a_column"),
        "not a column")
})
