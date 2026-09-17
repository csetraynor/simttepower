# Internal helpers shared across the package. Nothing here is exported.

`%||%` <- function(x, y) if (is.null(x)) y else x

# Every simtte::sim_tte_ode() argument an arm() call may set (everything
# except `model`/`n`, which arm() always requires explicitly, and `seed`,
# which the replication engine assigns per replicate -- never the caller).
.sim_tte_ode_extra_args <- c("param", "omega", "sigma", "end", "delta",
    "add", "idata", "data", "covariates", "beta", "formula", "knots",
    "boundary_knots", "coefs", "censoring", "visits", "keep_trajectory")

.sim_tte_ode_arg_names <- c("model", "n", .sim_tte_ode_extra_args)

#' Set a value at a one- or two-segment dotted path inside a list
#'
#' The only override mechanism scenario_grid()/new_scenario() use, for
#' every varied-factor type alike (a model parameter, a formula beta
#' entry, sample size, follow-up, ...). Deliberately not a general
#' recursive path-walker: the field set in play here never nests past two
#' levels (`"n"`, `"param.IC50"`), so a `strsplit()` on one dot is the
#' whole implementation (ponytail-audit, reports/01_phase1_plan.md).
#'
#' @noRd
.set_field <- function(x, field, value) {
    parts <- strsplit(field, ".", fixed = TRUE)[[1]]
    if (length(parts) == 1L) {
        x[[parts]] <- value
    } else if (length(parts) == 2L) {
        if (is.null(x[[parts[1]]])) x[[parts[1]]] <- list()
        x[[parts[1]]][[parts[2]]] <- value
    } else {
        stop("`field` paths support at most two dot-separated segments ",
            "('n' or 'param.IC50'), got: '", field, "'.", call. = FALSE)
    }
    x
}

#' rbind() a list of data frames, filling any column missing from one
#' frame with NA rather than erroring (base rbind() requires identical
#' columns; analyses/arms legitimately differ in which columns they
#' produce -- e.g. one arm declares `dose`, another doesn't).
#'
#' @noRd
.rbind_fill <- function(dfs) {
    dfs <- Filter(Negate(is.null), dfs)
    if (!length(dfs)) return(NULL)
    if (length(dfs) == 1L) return(dfs[[1]])
    all_cols <- unique(unlist(lapply(dfs, names)))
    dfs <- lapply(dfs, function(d) {
        missing <- setdiff(all_cols, names(d))
        for (m in missing) d[[m]] <- NA
        d[all_cols]
    })
    do.call(rbind, c(dfs, list(make.row.names = FALSE)))
}
