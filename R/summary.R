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
#'   `oc_label` (`"power"`/`"type_I_error"`/`NA`, see Details),
#'   `n_errors`, `median_runtime_sec`, and (when the analysed events
#'   carried them) `median_duration` and one `median_events_<arm>` per
#'   arm.
#'
#' @section `oc_label`, power vs. type I error:
#' `reject_rate` is the same statistic either way -- the fraction of
#' replicates a `reject` rule rejected on. `oc_label` names which
#' reading applies, read from the scenario's own declared `truth`
#' ([scenario_grid()]'s `truth` argument), never guessed: `"type_I_error"`
#' when `truth` is declared and every value in it is exactly `0` (a null
#' scenario -- there is no real effect, so a rejection is a false
#' positive by construction); `"power"` when `truth` is declared and any
#' value is non-zero; `NA` when no `truth` was declared for that
#' scenario at all -- `summary()` has nothing to read `oc_label` from,
#' and does not guess from the varied-factor values themselves (a
#' `param.IC50` of `1` is not necessarily "null" for every design). This
#' is a labelling convenience only, not a new statistic -- both readings
#' are `reject_rate`/`reject_se`, and a scenario with no `truth` is
#' still fully summarised, just without this one extra label.
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
        out$oc_label <- .oc_label(scn_truth[[out$scenario_id]])
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

# "power" vs. "type_I_error": read from a scenario's own declared
# truth, never guessed from varied-factor values. See summary()'s own
# "oc_label" doc section for why NULL/unset truth stays NA rather than
# a guess.
.oc_label <- function(truth) {
    if (is.null(truth) || !length(truth)) return(NA_character_)
    if (all(unlist(truth) == 0)) "type_I_error" else "power"
}

#' @export
print.simttepower_summary <- function(x, ...) {
    cat("<simttepower_summary>\n")
    print.data.frame(x, row.names = FALSE, ...)
    invisible(x)
}
