# .data is ggplot2/rlang's tidy-eval pronoun: aes() captures it as a bare
# symbol so ggplot2 can bind it to the real per-layer data mask at build
# time, which only works for the *unqualified* symbol (a `ggplot2::.data`
# reference resolves to a different, inert placeholder object instead --
# confirmed directly: it renders "Can't subset .data outside of a data
# mask context"). ggplot2 stays a Suggests dependency (not Imports), so
# `.data` can't be brought in via @importFrom either -- codetools'
# static analysis flags the bare symbol as an unbound global without
# this, which globalVariables() is the standard, dependency-free way to
# suppress; it creates no actual binding, so it does not interfere with
# the data-mask override above.
utils::globalVariables(".data")

#' Plot a power/operating-characteristic curve
#'
#' The common case: rejection rate (power, or type I error, depending on
#' the scenario) over one varied factor, from a [summary.simttepower_result()]
#' data frame. `ggplot2` is a `Suggests` dependency; `plot_power()` errors
#' clearly, telling the user to install it, if it isn't available.
#'
#' Deliberately just the one common shape (a curve, optionally coloured
#' by a second factor, optionally faceted by a third, with a binomial CI
#' ribbon) -- a user with a more exotic plot already has the tidy
#' `simttepower_summary` data frame `summary()` returns and can build
#' anything else directly with `ggplot2` (or another plotting package)
#' from it. The return value is an ordinary `ggplot` object, further
#' customisable with `+` the usual way (a theme, different labels, ...).
#'
#' @param summary A `"simttepower_summary"` (the output of
#'   [summary.simttepower_result()]).
#' @param x Character scalar: the varied-factor column to plot on the
#'   x-axis (e.g. `"n"`, `"IC50"` -- whatever [scenario_grid()]'s `over`
#'   named it).
#' @param y Character scalar, default `"reject_rate"`: the column to plot
#'   on the y-axis. The CI ribbon (`ci = TRUE`) only ever draws for the
#'   default -- it needs `reject_se`, which `summary()` only computes for
#'   `reject_rate`.
#' @param color Character scalar or `NULL` (default): a second
#'   varied-factor column to map to colour/fill (and the ribbon's
#'   grouping), for comparing curves across e.g. two arms' sample sizes.
#' @param facet Character scalar or `NULL` (default): a third
#'   varied-factor column to facet by (`ggplot2::facet_wrap()`).
#' @param ci Logical, default `TRUE`: draw a 95% binomial CI ribbon
#'   (`reject_rate +/- 1.96 * reject_se`, clipped to `[0, 1]`) around the
#'   curve. Only takes effect when `y = "reject_rate"` (the default) and
#'   `summary` carries `reject_se`; silently skipped otherwise.
#'
#' @return A `ggplot` object.
#' @seealso [summary.simttepower_result()], [power_sim()]
#' @examples
#' \donttest{
#' if (requireNamespace("ggplot2", quietly = TRUE)) {
#'   comparator <- arm(label = "comparator", n = 30, model = "irm1_hazard",
#'     end = 24, param = list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5,
#'       IC50 = 1, IMAX = 0.9, H0 = 0.15))
#'   experimental <- arm(label = "experimental", n = 30, model = "irm1_hazard",
#'     end = 24, param = list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5,
#'       IC50 = 3, IMAX = 0.9, H0 = 0.15))
#'   design <- trial_design(arms = list(comparator, experimental),
#'     analyses = list(coxph = analysis_coxph))
#'   grid <- scenario_grid(design, over = list(arm = "experimental",
#'     field = "n", values = c(30, 60, 90)))
#'   res <- power_sim(grid, n_sims = 5, seed = 1, progress = FALSE)
#'   plot_power(summary(res), x = "n")
#' }
#' }
#' @export
plot_power <- function(summary, x, y = "reject_rate", color = NULL,
    facet = NULL, ci = TRUE) {
    if (!requireNamespace("ggplot2", quietly = TRUE)) {
        stop("plot_power() needs the ggplot2 package. Install it with ",
            "install.packages(\"ggplot2\").", call. = FALSE)
    }
    if (!inherits(summary, "simttepower_summary")) {
        stop("`summary` must be a simttepower_summary -- the output of ",
            "summary(power_sim(...)).", call. = FALSE)
    }
    cols <- names(summary)
    for (nm in list(x = x, y = y, color = color, facet = facet)) {
        if (!is.null(nm) && !nm %in% cols) {
            stop("'", nm, "' is not a column of `summary` (has: ",
                paste(cols, collapse = ", "), ").", call. = FALSE)
        }
    }

    d <- as.data.frame(summary)
    if (!is.null(color)) d[[color]] <- factor(d[[color]])

    mapping <- if (is.null(color)) {
        ggplot2::aes(x = .data[[x]], y = .data[[y]])
    } else {
        ggplot2::aes(x = .data[[x]], y = .data[[y]],
            colour = .data[[color]], group = .data[[color]])
    }
    p <- ggplot2::ggplot(d, mapping)

    draw_ci <- isTRUE(ci) && identical(y, "reject_rate") &&
        "reject_se" %in% cols
    if (draw_ci) {
        ribbon_mapping <- if (is.null(color)) {
            ggplot2::aes(
                ymin = pmax(0, .data[[y]] - 1.96 * .data[["reject_se"]]),
                ymax = pmin(1, .data[[y]] + 1.96 * .data[["reject_se"]]))
        } else {
            ggplot2::aes(
                ymin = pmax(0, .data[[y]] - 1.96 * .data[["reject_se"]]),
                ymax = pmin(1, .data[[y]] + 1.96 * .data[["reject_se"]]),
                fill = .data[[color]], group = .data[[color]])
        }
        p <- p + ggplot2::geom_ribbon(ribbon_mapping, alpha = 0.15, colour = NA)
    }

    p <- p + ggplot2::geom_line() + ggplot2::geom_point()
    if (!is.null(facet)) {
        p <- p + ggplot2::facet_wrap(stats::as.formula(paste("~", facet)))
    }
    if (identical(y, "reject_rate")) {
        p <- p + ggplot2::labs(y = "Rejection rate")
    }
    p
}
