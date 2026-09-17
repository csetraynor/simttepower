# Internal scenario representation. Not exported, not a public
# constructor: scenario_grid() with a single-value `values` already
# builds exactly one scenario, so a separate public scenario()
# constructor would just be a redundant single-purpose factory
# (ponytail-audit, reports/01_phase1_plan.md).

#' Apply one or more overrides to a trial_design, producing a scenario
#'
#' @param design A `simttepower_trial_design`.
#' @param overrides A list of `list(arm = <label or NULL>, field = <chr>,
#'   value = <any>)`. `arm = NULL` means a trial-level field (currently
#'   only `"end"`).
#' @param scenario_id Character scalar.
#' @param varied A named list of the values this scenario represents (for
#'   the grid's own label columns).
#' @param truth Optional named numeric, or NULL.
#' @noRd
.new_scenario <- function(design, overrides, scenario_id, varied = list(),
    truth = NULL) {
    resolved <- design
    for (ov in overrides) {
        if (is.null(ov$arm)) {
            resolved <- .set_field(resolved, ov$field, ov$value)
        } else {
            ix <- match(ov$arm, vapply(resolved$arms, `[[`, "", "label"))
            if (is.na(ix)) {
                stop("scenario_grid(): no arm labeled '", ov$arm,
                    "' in this design.", call. = FALSE)
            }
            resolved$arms[[ix]] <- .set_field(resolved$arms[[ix]], ov$field,
                ov$value)
        }
    }
    structure(list(scenario_id = scenario_id, design = resolved,
        varied = varied, truth = truth), class = "simttepower_scenario")
}

#' Check one override's `field` resolves against a design, before any
#' scenario is built from it -- fail at grid-build time, not mid-replication.
#' @noRd
.validate_override_field <- function(design, arm_label, field) {
    # A real .set_field() probe (rather than re-checking segment count by
    # hand) isn't safe here: assigning NULL two segments deep removes an
    # element for a list-valued top field (`param`) but errors for an
    # atomic-vector-valued one (`beta`) -- a real mutation's semantics
    # differ by target type, so validation checks shape directly instead.
    parts <- strsplit(field, ".", fixed = TRUE)[[1]]
    if (!length(parts) %in% 1:2) {
        stop("`field` paths support at most two dot-separated segments, ",
            "got: '", field, "'.", call. = FALSE)
    }
    if (is.null(arm_label)) {
        if (!identical(field, "end")) {
            stop("Trial-level (arm = NULL) overrides only support ",
                "field = \"end\"; got '", field, "'.", call. = FALSE)
        }
        return(invisible(TRUE))
    }
    ix <- match(arm_label, vapply(design$arms, `[[`, "", "label"))
    if (is.na(ix)) {
        stop("scenario_grid(): no arm labeled '", arm_label,
            "' in this design.", call. = FALSE)
    }
    invisible(TRUE)
}
