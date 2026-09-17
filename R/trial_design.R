#' Define a trial: arms plus the analyses run on each replicate
#'
#' @param arms A list of [arm()] objects. At least one; labels must be
#'   unique. Single-arm designs are allowed (simtte itself is
#'   single-cohort) -- `trial_design()` does not assume a comparison.
#' @param analyses A named list of analysis functions, each with the
#'   contract `function(events, ...) -> named numeric` (see
#'   [analysis_coxph()], [analysis_logrank()], and the "Analysis
#'   functions" section of `reports/01_phase1_plan.md`). The names become
#'   the `analysis` column in `power_sim()` results.
#' @param end Optional trial-level follow-up, used for any arm that does
#'   not set its own `end`. An arm's own `end` (via `arm(..., end = )`,
#'   part of its `...` passthrough to `sim_tte_ode()`) always wins.
#'
#' @return A `"simttepower_trial_design"` object (a list).
#' @seealso [arm()], [scenario_grid()], [power_sim()]
#' @examples
#' design <- trial_design(
#'   arms = list(
#'     arm(label = "comparator", n = 100, model = "irm1_hazard", end = 24,
#'       param = list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5,
#'         IC50 = 1, IMAX = 0.9, H0 = 0.15)),
#'     arm(label = "experimental", n = 100, model = "irm1_hazard", end = 24,
#'       param = list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5,
#'         IC50 = 2, IMAX = 0.9, H0 = 0.15))
#'   ),
#'   analyses = list(coxph = analysis_coxph, logrank = analysis_logrank)
#' )
#' design
#' @export
trial_design <- function(arms, analyses, end = NULL) {
    if (!is.list(arms) || !length(arms) ||
        !all(vapply(arms, inherits, logical(1), "simttepower_arm"))) {
        stop("`arms` must be a non-empty list of arm() objects.",
            call. = FALSE)
    }
    labels <- vapply(arms, `[[`, "", "label")
    if (anyDuplicated(labels)) {
        stop("Arm labels must be unique; got: ",
            paste(labels, collapse = ", "), ".", call. = FALSE)
    }
    if (!is.list(analyses) || !length(analyses) ||
        is.null(names(analyses)) || any(!nzchar(names(analyses))) ||
        !all(vapply(analyses, is.function, logical(1)))) {
        stop("`analyses` must be a non-empty named list of functions.",
            call. = FALSE)
    }
    if (!is.null(end) && (!is.numeric(end) || length(end) != 1L)) {
        stop("`end` must be a single numeric value, or NULL.", call. = FALSE)
    }

    structure(list(arms = arms, analyses = analyses, end = end),
        class = "simttepower_trial_design")
}

#' @export
print.simttepower_trial_design <- function(x, ...) {
    cat(sprintf("<simttepower_trial_design> %d arm(s), %d analysis(es)\n",
        length(x$arms), length(x$analyses)))
    for (a in x$arms) {
        cat(sprintf("  - %s (n = %d)\n", a$label, a$n))
    }
    cat(sprintf("  analyses: %s\n", paste(names(x$analyses), collapse = ", ")))
    invisible(x)
}
