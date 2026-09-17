#' Rejection rules for power_sim()/summary()
#'
#' A rejection rule is `function(row, alpha, ...) -> logical(1)`, applied
#' to one row of `power_sim()`'s results (one scenario × replicate ×
#' analysis). `reject_default()` is `p < alpha`, auto-detecting the
#' p-value column. `reject_direction()` additionally requires the
#' estimate's sign to match a scenario's own `truth` (see the `truth`
#' argument of [scenario_grid()]) -- decision 2 in
#' `reports/02_author_decisions.md`: a two-sided test that rejects in the
#' *wrong* direction should not count as a "win," but this is a pluggable
#' rule, not something baked into [analysis_coxph()] itself.
#'
#' @param row A single-row data frame or a named list/vector -- one
#'   `power_sim()` result row.
#' @param alpha Significance level. Default `0.05`.
#' @param p_col,estimate_col Explicit column name(s) to use, overriding
#'   auto-detection. Needed when a row has more than one `p_*`/`estimate_*`
#'   column (e.g. a multi-arm `~ arm` fit) and the rule can't tell which
#'   one you mean.
#' @param truth For `reject_direction()`: a named numeric giving the true
#'   sign to check against (usually a scenario's own `$truth`, read
#'   automatically by `summary()` -- see [scenario_grid()]'s `truth`
#'   argument). Not needed when calling `reject_direction()` directly
#'   with `estimate_col` set and a scalar truth.
#'
#' @return `TRUE`/`FALSE`. Always `FALSE` (never `NA`) when a needed
#'   value is missing, e.g. a non-converged fit.
#' @seealso [power_sim()], [scenario_grid()]
#' @export
reject_default <- function(row, alpha = 0.05, p_col = NULL) {
    p <- .pick_named(row, p_col, "p")
    if (is.null(p) || is.na(p)) return(FALSE)
    p < alpha
}

#' @rdname reject_default
#' @export
reject_direction <- function(row, truth, alpha = 0.05, p_col = NULL,
    estimate_col = NULL) {
    p <- .pick_named(row, p_col, "p")
    if (is.null(p) || is.na(p)) return(FALSE)
    est_pick <- .pick_estimate_and_truth(row, truth, estimate_col)
    if (is.null(est_pick) || is.na(est_pick$estimate) ||
        is.na(est_pick$truth)) {
        return(FALSE)
    }
    (p < alpha) && (sign(est_pick$estimate) == sign(est_pick$truth))
}

.row_value <- function(row, name) {
    if (is.null(row) || !name %in% names(row)) return(NULL)
    v <- row[[name]]
    if (length(v) != 1L) return(NULL)
    as.numeric(v)
}

.pick_named <- function(row, explicit_col, prefix) {
    if (!is.null(explicit_col)) return(.row_value(row, explicit_col))
    if (prefix %in% names(row)) return(.row_value(row, prefix))
    cands <- grep(paste0("^", prefix, "_"), names(row), value = TRUE)
    if (length(cands) == 1L) return(.row_value(row, cands))
    if (length(cands) > 1L) {
        stop("Cannot auto-detect a single '", prefix, "' column (candidates: ",
            paste(cands, collapse = ", "), "); pass ", prefix, "_col ",
            "explicitly.", call. = FALSE)
    }
    NULL
}

.pick_estimate_and_truth <- function(row, truth, estimate_col) {
    if (is.null(truth) || !length(truth)) return(NULL)
    if (!is.null(estimate_col)) {
        return(list(estimate = .row_value(row, estimate_col),
            truth = unname(truth[[estimate_col]])))
    }
    common <- intersect(names(truth), names(row))
    if (length(common) == 1L) {
        return(list(estimate = .row_value(row, common),
            truth = unname(truth[[common]])))
    }
    if (length(common) > 1L) {
        stop("Cannot auto-match a single truth/estimate column (candidates: ",
            paste(common, collapse = ", "), "); pass estimate_col ",
            "explicitly.", call. = FALSE)
    }
    NULL
}
