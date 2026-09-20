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
