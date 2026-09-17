#' Define one trial arm
#'
#' One arm = the argument set [simtte::sim_tte_ode()] needs to simulate
#' that arm, plus a label. `arm()` does not re-validate simulation
#' arguments (`param`, `omega`, `censoring`, `visits`, ...) beyond basic
#' shape checks -- that is `sim_tte_ode()`'s own job, and duplicating it
#' here would mean two places that can disagree.
#'
#' Estimand boundary (see `reports/01_phase1_plan.md` addendum, "Estimand
#' scope and group labels"): simulation-side parameters (`param`, dose,
#' `covariates`) are *truth* in a scenario, not something an analysis
#' function estimates. `dose` and `regimen` below only ever label what a
#' scenario used; simttepower never computes a "the dose" scalar for you.
#'
#' @param label Character scalar. Arm name; used as the `arm` column in
#'   simulated events and, by default, as `regimen`.
#' @param n Positive whole number of subjects.
#' @param model A model name from [simtte::sim_tte_ode_models()] or a
#'   `"simtte_model"` object from [simtte::tte_model()].
#' @param regimen Character scalar, optional. A label for this arm's
#'   dosing regimen, independent of `label` (e.g. two arms sharing the
#'   same `label` prefix but different schedules). Defaults to `label`.
#'   Never derived from `data`/`add` -- a regimen such as loading-then-
#'   maintenance dosing has no single meaningful numeric summary, so
#'   simttepower does not invent one.
#' @param dose Numeric scalar, optional. A user-declared dose summary for
#'   this arm (e.g. for a dose-trend analysis via
#'   `analysis_coxph(formula = ~ dose)`). Used exactly as given; never
#'   computed (an earlier draft attached a computed `cum_dose` column; cut
#'   after Phase 1 -- wrong for `addl`/`ii` regimens, and not needed since
#'   groups are the `arm`/`regimen` labels).
#' @param ... Any other [simtte::sim_tte_ode()] argument: `param`,
#'   `omega`, `sigma`, `end`, `delta`, `add`, `idata`, `data`,
#'   `covariates`, `beta`, `formula`, `knots`, `boundary_knots`, `coefs`,
#'   `censoring`, `visits`, `keep_trajectory`. Not `seed` -- the
#'   replication engine assigns that per replicate.
#'
#' @return A `"simttepower_arm"` object (a list).
#' @seealso [trial_design()], [scenario_grid()]
#' @examples
#' arm(
#'   label = "comparator", n = 100, model = "irm1_hazard", end = 24,
#'   param = list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5,
#'     IC50 = 1, IMAX = 0.9, H0 = 0.15)
#' )
#' @export
arm <- function(label, n, model, regimen = NULL, dose = NULL, ...) {
    if (!is.character(label) || length(label) != 1L || !nzchar(label)) {
        stop("`label` must be a single non-empty character string.",
            call. = FALSE)
    }
    if (!is.numeric(n) || length(n) != 1L || n <= 0 || n != round(n)) {
        stop("`n` must be a single positive whole number.", call. = FALSE)
    }
    n <- as.integer(n)
    .validate_arm_model(model)
    if (!is.null(dose) && (!is.numeric(dose) || length(dose) != 1L)) {
        stop("`dose` must be a single numeric value, or NULL.", call. = FALSE)
    }
    if (!is.null(regimen) &&
        (!is.character(regimen) || length(regimen) != 1L)) {
        stop("`regimen` must be a single character string, or NULL.",
            call. = FALSE)
    }

    dots <- list(...)
    if ("seed" %in% names(dots)) {
        stop("`seed` is assigned per replicate by the replication engine, ",
            "not by arm(). Remove `seed` from this call.", call. = FALSE)
    }
    unknown <- setdiff(names(dots), .sim_tte_ode_extra_args)
    if (length(unknown)) {
        stop("Unknown argument(s) to arm(): ", paste(unknown, collapse = ", "),
            ". arm() only forwards simtte::sim_tte_ode() arguments -- see ",
            "?sim_tte_ode.", call. = FALSE)
    }

    # No re-defaulting of param/delta/keep_trajectory here (ponytail-review):
    # an unset field simply isn't in `dots`, so do.call(sim_tte_ode, ...)
    # falls through to sim_tte_ode()'s own identical defaults, and
    # .set_field() already initializes an absent `param` on demand.
    structure(
        c(list(label = label, n = n, model = model,
            regimen = regimen %||% label, dose = dose), dots),
        class = "simttepower_arm"
    )
}

.validate_arm_model <- function(model) {
    if (inherits(model, "simtte_model")) return(invisible(TRUE))
    if (is.character(model) && length(model) == 1L) {
        known <- simtte::sim_tte_ode_models()$model
        if (model %in% known) return(invisible(TRUE))
        stop("`model` = \"", model, "\" is not one of simtte's built-in ",
            "models (", paste(known, collapse = ", "), "). Use one of ",
            "those, or a simtte::tte_model() object.", call. = FALSE)
    }
    stop("`model` must be a built-in model name (see ",
        "simtte::sim_tte_ode_models()) or a simtte::tte_model() object.",
        call. = FALSE)
}

#' @export
print.simttepower_arm <- function(x, ...) {
    model_label <- if (inherits(x$model, "simtte_model")) {
        x$model$name %||% "<tte_model>"
    } else {
        x$model
    }
    cat(sprintf("<simttepower_arm> %s\n", x$label))
    cat(sprintf("  model:   %s\n", model_label))
    cat(sprintf("  n:       %d\n", x$n))
    cat(sprintf("  regimen: %s%s\n", x$regimen,
        if (!is.null(x$dose)) sprintf("  (dose = %s)", format(x$dose)) else ""))
    if (length(x$param)) {
        cat(sprintf("  param:   %s\n",
            paste(names(x$param), unlist(x$param), sep = " = ", collapse = ", ")))
    }
    invisible(x)
}
