#' Build a grid of scenarios from a base trial design
#'
#' Crosses a base [trial_design()] against one or more varied factors.
#' Every factor type -- a model parameter, a nonlinear-link parameter, a
#' formula coefficient, a dosing regimen, a sampling schedule, sample
#' size, follow-up, or a covariate distribution -- goes through the same
#' `over` entry shape; nothing about `scenario_grid()` special-cases any
#' of them (see `reports/01_phase1_plan.md` section 2).
#'
#' @param design A `simttepower_trial_design` (see [trial_design()]).
#' @param over One `over` entry, or a list of them, crossed
#'   (`expand.grid()`-style) when more than one is given. Each entry is a
#'   list with:
#'   \describe{
#'     \item{`arm`}{Character, the arm label to override, or `NULL` for a
#'       trial-level field (currently only `"end"`).}
#'     \item{`field`}{A one- or two-segment dotted path: `"n"`, `"end"`,
#'       `"data"`, `"visits"`, `"covariates"`, or `"param.<name>"` /
#'       `"beta.<name>"` for a nested entry.}
#'     \item{`values`}{The candidate values for this factor: an atomic
#'       vector for a scalar factor (`n`, a `param`/`beta` entry), or a
#'       list for a factor whose values are themselves objects (`data`,
#'       `visits`, `covariates`).}
#'     \item{`name`}{Optional column name override, if the default
#'       (the field's last path segment) collides with another entry.}
#'   }
#' @param truth Optional. Either a function of one scenario's varied
#'   values (a named list, one entry per `over` factor) returning a named
#'   numeric matching an analysis function's own output names (e.g.
#'   `c(estimate_armexperimental = log(0.7))`), or a list of such named
#'   numerics, one per resulting scenario, in grid row order. Read only
#'   by a direction-aware `reject` rule in `power_sim()`/`summary()` (see
#'   [reject_direction()]) -- Phase 1 does not compute bias/coverage from
#'   it.
#'
#' @return A `"simttepower_scenario_grid"` data frame: one row per
#'   scenario, a column per varied factor, `scenario_id`, and a
#'   list-column `scenario` holding the resolved internal scenario object
#'   each row's replicates are built from.
#' @seealso [trial_design()], [power_sim()]
#' @examples
#' comparator <- arm(label = "comparator", n = 100, model = "irm1_hazard",
#'   end = 24, param = list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5,
#'     IC50 = 1, IMAX = 0.9, H0 = 0.15))
#' experimental <- arm(label = "experimental", n = 100, model = "irm1_hazard",
#'   end = 24, param = list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5,
#'     IC50 = 1, IMAX = 0.9, H0 = 0.15))
#' design <- trial_design(arms = list(comparator, experimental),
#'   analyses = list(coxph = analysis_coxph))
#'
#' # vary the nonlinear-link IC50 parameter on the experimental arm
#' grid <- scenario_grid(design, over = list(arm = "experimental",
#'   field = "param.IC50", values = c(0.5, 1, 2, 4)))
#' grid
#' @export
scenario_grid <- function(design, over, truth = NULL) {
    if (!inherits(design, "simttepower_trial_design")) {
        stop("`design` must be a trial_design() object.", call. = FALSE)
    }
    if (!is.list(over) || !length(over)) {
        stop("`over` must be a non-empty list.", call. = FALSE)
    }
    if (!is.null(over$field)) over <- list(over)  # a single entry, unwrapped
    for (spec in over) {
        if (is.null(spec$field) || is.null(spec$values) ||
            !length(spec$values)) {
            stop("Every `over` entry needs `field` and a non-empty ",
                "`values`.", call. = FALSE)
        }
        .validate_override_field(design, spec$arm, spec$field)
    }
    if (!is.null(truth) && !is.function(truth) && !is.list(truth)) {
        stop("`truth` must be NULL, a function, or a list.", call. = FALSE)
    }

    colnames <- vapply(over, .factor_colname, "")
    if (anyDuplicated(colnames)) {
        stop("scenario_grid(): duplicate factor column name(s): ",
            paste(unique(colnames[duplicated(colnames)]), collapse = ", "),
            ". Give one entry an explicit `name =`.", call. = FALSE)
    }

    lens <- vapply(over, function(s) length(s$values), integer(1))
    combos <- expand.grid(lapply(lens, seq_len), KEEP.OUT.ATTRS = FALSE)
    names(combos) <- colnames
    n_scn <- nrow(combos)

    if (is.list(truth) && !is.function(truth) && length(truth) != n_scn) {
        stop("`truth` is a list of length ", length(truth), " but the grid ",
            "has ", n_scn, " scenarios; supply one truth per scenario, in ",
            "row order.", call. = FALSE)
    }

    rows <- vector("list", n_scn)
    for (i in seq_len(n_scn)) {
        overrides <- lapply(seq_along(over), function(j) {
            list(arm = over[[j]]$arm, field = over[[j]]$field,
                value = over[[j]]$values[[combos[i, j]]])
        })
        varied <- stats::setNames(
            lapply(seq_along(over), function(j) over[[j]]$values[[combos[i, j]]]),
            colnames)
        scn_truth <- if (is.function(truth)) truth(varied)
            else if (is.list(truth)) truth[[i]] else NULL
        rows[[i]] <- .new_scenario(design, overrides, paste0("s", i), varied,
            scn_truth)
    }

    grid_df <- data.frame(scenario_id = vapply(rows, `[[`, "", "scenario_id"),
        stringsAsFactors = FALSE)
    for (cn in colnames) grid_df[[cn]] <- .varied_column(rows, cn)
    grid_df$scenario <- rows
    structure(grid_df, class = c("simttepower_scenario_grid", class(grid_df)))
}

.factor_colname <- function(spec) {
    if (!is.null(spec$name)) return(spec$name)
    parts <- strsplit(spec$field, ".", fixed = TRUE)[[1]]
    parts[length(parts)]
}

.varied_column <- function(rows, cn) {
    vals <- lapply(rows, function(r) r$varied[[cn]])
    scalar <- vapply(vals, function(v) is.atomic(v) && length(v) == 1L,
        logical(1))
    if (all(scalar)) unlist(vals) else vals
}

#' @export
print.simttepower_scenario_grid <- function(x, ...) {
    factor_cols <- setdiff(names(x), c("scenario_id", "scenario"))
    cat(sprintf("<simttepower_scenario_grid> %d scenario(s), varied: %s\n",
        nrow(x), paste(factor_cols, collapse = ", ")))
    display <- data.frame(scenario_id = x$scenario_id, stringsAsFactors = FALSE)
    for (cn in factor_cols) {
        col <- x[[cn]]
        display[[cn]] <- if (is.list(col)) {
            vapply(col, function(v) sprintf("<%s>", class(v)[1]), "")
        } else {
            col
        }
    }
    print(display, row.names = FALSE)
    invisible(x)
}
