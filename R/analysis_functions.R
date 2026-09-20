#' Built-in analysis functions
#'
#' The analysis-function contract is `function(events, ...) -> named
#' numeric`. `events` is whatever [power_sim()] assembles for one
#' replicate: every arm's `sim_tte_ode()` events, row-bound, with `arm`
#' (and, when set, `regimen`, `dose`, and any `covariates` columns)
#' already joined on by the engine (see
#' `reports/01_phase1_plan.md` addendum, "Estimand scope and group
#' labels"). Both built-ins here are guarded: calling either without the
#' `survival` package installed gives a clear error, not a cryptic one.
#'
#' @param events A data frame (see Details).
#' @param formula A one-sided formula for the right-hand side of
#'   `survival::coxph(survival::Surv(sim_time, sim_status) ~ <formula>,
#'   ...)`. Default `~ arm`. Any column `power_sim()` attached to
#'   `events` can appear here: `~ regimen`, `~ dose` (only when the arm
#'   declared one), `~ dose + age`, `~ arm * sex`, and so on. For a
#'   design with more than two arms, `~ arm` (with `arm` as a factor
#'   levelled in the design's own arm order -- see [trial_design()])
#'   gives `k - 1` contrasts against the first arm.
#' @param time_var,status_var Column names in `events` for
#'   `survival::Surv()`. Defaults match `sim_tte_ode()`'s own output
#'   (`"sim_time"`, `"sim_status"`).
#' @param ... Passed on to `survival::coxph()`.
#'
#' @return A named numeric vector. `analysis_coxph()` returns, for every
#'   term `coxph()` fits (named by `coxph()`'s own term/dummy-level
#'   name): `estimate_<term>` (log-HR), `se_<term>`, `p_<term>`,
#'   `hr_<term>`, `hr_lo_<term>`, `hr_hi_<term>`; plus `converged` (`1`
#'   if the fit succeeded, `0` otherwise, with every other value `NA`).
#' @examples
#' \donttest{
#' comparator <- arm(label = "comparator", n = 60, model = "irm1_hazard",
#'   end = 24, param = list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5,
#'     IC50 = 1, IMAX = 0.9, H0 = 0.15))
#' experimental <- arm(label = "experimental", n = 60, model = "irm1_hazard",
#'   end = 24, param = list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5,
#'     IC50 = 3, IMAX = 0.9, H0 = 0.15))
#' events <- rbind(
#'   cbind(simtte::sim_tte_ode(comparator$model, param = comparator$param,
#'     n = comparator$n, end = comparator$end, seed = 1)$events,
#'     arm = "comparator"),
#'   cbind(simtte::sim_tte_ode(experimental$model, param = experimental$param,
#'     n = experimental$n, end = experimental$end, seed = 2)$events,
#'     arm = "experimental")
#' )
#' analysis_coxph(events)
#' analysis_logrank(events)
#' }
#' @seealso [trial_design()] (where an analysis function is registered),
#'   [reject_default()], [reject_direction()]
#' @name analysis_functions
NULL

#' @rdname analysis_functions
#' @export
analysis_coxph <- function(events, formula = ~arm, time_var = "sim_time",
    status_var = "sim_status", ...) {
    .require_survival("analysis_coxph")
    rhs <- .formula_rhs_string(formula)
    surv_formula <- stats::as.formula(paste0("survival::Surv(", time_var,
        ", ", status_var, ") ~ ", rhs))

    fit <- tryCatch(survival::coxph(surv_formula, data = events, ...),
        error = function(e) e)
    if (inherits(fit, "error")) {
        return(c(converged = 0))
    }
    s <- summary(fit)
    cm <- s$coefficients
    ci <- s$conf.int
    tn <- rownames(cm)
    out <- c(
        stats::setNames(cm[, "coef"], paste0("estimate_", tn)),
        stats::setNames(cm[, "se(coef)"], paste0("se_", tn)),
        stats::setNames(cm[, "Pr(>|z|)"], paste0("p_", tn)),
        stats::setNames(ci[, "exp(coef)"], paste0("hr_", tn)),
        stats::setNames(ci[, "lower .95"], paste0("hr_lo_", tn)),
        stats::setNames(ci[, "upper .95"], paste0("hr_hi_", tn))
    )
    c(out, converged = 1)
}

#' @rdname analysis_functions
#' @param group Column name in `events` defining the groups compared.
#'   Default `"arm"`.
#' @export
analysis_logrank <- function(events, group = "arm", time_var = "sim_time",
    status_var = "sim_status", ...) {
    .require_survival("analysis_logrank")
    f <- stats::as.formula(paste0("survival::Surv(", time_var, ", ",
        status_var, ") ~ ", group))
    fit <- tryCatch(survival::survdiff(f, data = events, ...),
        error = function(e) e)
    if (inherits(fit, "error")) {
        return(c(p = NA_real_, converged = 0))
    }
    p <- stats::pchisq(fit$chisq, df = length(fit$n) - 1, lower.tail = FALSE)
    c(p = unname(p), converged = 1)
}

.require_survival <- function(caller) {
    if (!requireNamespace("survival", quietly = TRUE)) {
        stop(caller, "() needs the 'survival' package. Install it with ",
            "install.packages(\"survival\").", call. = FALSE)
    }
}

.formula_rhs_string <- function(formula) {
    if (!inherits(formula, "formula") || length(formula) != 2L) {
        stop("`formula` must be one-sided, e.g. ~ arm or ~ dose + age.",
            call. = FALSE)
    }
    paste(deparse(formula[[2]]), collapse = " ")
}
