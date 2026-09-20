#' Summarise a power_sim() result
#'
#' A separate function from [power_sim()] itself (see
#' `reports/01_phase1_plan.md` section 6): `power_sim()` returns the raw
#' per-replicate results; `summary()` collapses them to one row per
#' (scenario x analysis) operating-characteristic summary.
#'
#' @param object A `"simttepower_result"` from [power_sim()].
#' @param ... Extra named arguments forwarded to the result's `reject`
#'   rule (e.g. `p_col = "p_armexperimental"` when a row has more than
#'   one candidate p-value column -- see [reject_default()]).
#'
#' @return A `"simttepower_summary"` data frame, one row per
#'   scenario x analysis: the scenario's varied-factor columns,
#'   `n_sims`, `reject_rate` and its binomial SE (`reject_se`),
#'   `n_errors`, `median_runtime_sec`, and (when the analysed events
#'   carried them) `median_duration` and one `median_events_<arm>` per
#'   arm.
#' @seealso [power_sim()], [reject_default()], [plot_power()]
#' @examples
#' \donttest{
#' comparator <- arm(label = "comparator", n = 30, model = "irm1_hazard",
#'   end = 24, param = list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5,
#'     IC50 = 1, IMAX = 0.9, H0 = 0.15))
#' experimental <- arm(label = "experimental", n = 30, model = "irm1_hazard",
#'   end = 24, param = list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5,
#'     IC50 = 3, IMAX = 0.9, H0 = 0.15))
#' design <- trial_design(arms = list(comparator, experimental),
#'   analyses = list(coxph = analysis_coxph))
#' grid <- scenario_grid(design, over = list(arm = "experimental",
#'   field = "n", values = c(30, 60)))
#' res <- power_sim(grid, n_sims = 5, seed = 1, progress = FALSE)
#' summary(res)
#' }
#' @export
summary.simttepower_result <- function(object, ...) {
    res <- object$results
    reject_fn <- object$reject
    alpha <- object$alpha
    extra_args <- list(...)
    truth_supported <- "truth" %in% names(formals(reject_fn))

    grid <- object$grid
    scn_truth <- stats::setNames(lapply(grid$scenario, `[[`, "truth"),
        grid$scenario_id)

    res$.reject <- vapply(seq_len(nrow(res)), function(i) {
        row <- res[i, , drop = FALSE]
        args <- c(list(row = row, alpha = alpha), extra_args)
        if (truth_supported) args$truth <- scn_truth[[row$scenario_id]]
        isTRUE(tryCatch(do.call(reject_fn, args), error = function(e) FALSE))
    }, logical(1))

    group_cols <- c("scenario_id",
        setdiff(names(grid), c("scenario_id", "scenario")), "analysis")
    grp_key <- do.call(paste, c(res[group_cols], list(sep = "\r")))
    n_events_cols <- grep("^n_events_", names(res), value = TRUE)
    has_duration <- "duration" %in% names(res)

    groups <- split(seq_len(nrow(res)), grp_key)
    rows <- lapply(groups, function(ix) {
        grp <- res[ix, , drop = FALSE]
        n <- nrow(grp)
        p_reject <- mean(grp$.reject)
        out <- grp[1, group_cols, drop = FALSE]
        out$n_sims <- n
        out$reject_rate <- p_reject
        out$reject_se <- sqrt(p_reject * (1 - p_reject) / n)
        out$n_errors <- sum(!is.na(grp$error))
        out$median_runtime_sec <- stats::median(grp$runtime_sec, na.rm = TRUE)
        if (has_duration) {
            out$median_duration <- stats::median(grp$duration, na.rm = TRUE)
        }
        for (cn in n_events_cols) {
            out[[gsub("^n_events_", "median_events_", cn)]] <-
                stats::median(grp[[cn]], na.rm = TRUE)
        }
        out
    })
    out <- .rbind_fill(rows)
    rownames(out) <- NULL
    structure(out, class = c("simttepower_summary", class(out)))
}

#' @export
print.simttepower_summary <- function(x, ...) {
    cat("<simttepower_summary>\n")
    print.data.frame(x, row.names = FALSE, ...)
    invisible(x)
}
