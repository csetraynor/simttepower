#' Run the sequential replication engine
#'
#' Simulates and analyses every (scenario x replicate) in `grid`,
#' sequentially -- no parallelism (that's Phase 2). See
#' `reports/01_phase1_plan.md` sections 5 and 7 for the L'Ecuyer
#' RNG-stream design this function implements: replicate `k` of scenario
#' `s` always draws from the same random stream, regardless of how many
#' workers a later phase runs it with.
#'
#' **Estimand boundary** (`reports/01_phase1_plan.md` addendum):
#' simulation-side parameters (a `param`/`beta` entry, dose, covariate
#' distribution) are *truth* baked into a scenario, never something an
#' analysis function estimates here. `power_sim()` only ever asks an
#' analysis function to estimate a contrast/coefficient from the observed
#' `events` and the labels it attaches (`arm`, `regimen`, `dose` when
#' declared, and any `covariates` columns, joined at baseline).
#' Estimating a nonlinear PK/PD parameter from event data is out of
#' scope; bring your own analysis function for that.
#'
#' @param grid A `simttepower_scenario_grid` (see [scenario_grid()]).
#' @param n_sims Replicates per scenario (the same for every scenario --
#'   Phase 1 assumes a rectangular grid).
#' @param seed A single base seed. The full seed, not a per-arm or
#'   per-worker one: `power_sim(grid, n_sims = 50, seed = 1)` run twice
#'   gives byte-identical `results`.
#' @param reject A rejection rule, `function(row, alpha, ...) -> logical`.
#'   Default [reject_default()] (`p < alpha`); see [reject_direction()]
#'   for a direction-aware alternative. Stored on the result and used by
#'   [summary.simttepower_result()]; not applied by `power_sim()` itself.
#' @param alpha Significance level passed to `reject`. Default `0.05`.
#' @param progress Show progress. Sequentially (`workers = 1`), a text
#'   progress bar; in parallel, a start/finish message only -- no
#'   per-replicate callback from a worker. Default `interactive()`.
#' @param workers Number of local worker processes. `1` (default) is the
#'   sequential path above, byte-for-byte unchanged: no cluster is
#'   created, replicate `k` of scenario `s` is simulated exactly as in
#'   Phase 1. `workers > 1` dispatches across that many local processes
#'   (see `reports/04_phase2_design.md`); `power_sim(seed = s, workers =
#'   1)` and `workers > 1` give byte-identical `results` (excluding
#'   `runtime_sec`) -- the L'Ecuyer stream a task uses depends only on
#'   its `(scenario, replicate)` identity, never on which worker ran it
#'   or when. Ignored (with a message) when `cluster` is supplied --
#'   the cluster's own size is used instead.
#' @param cluster An existing `parallel` cluster (from
#'   `parallel::makeCluster()`/`makePSOCKcluster()`), or `NULL` (default).
#'   `NULL` with `workers > 1` creates a `parallel::makePSOCKcluster()`
#'   internally and stops it when `power_sim()` returns, error or not. A
#'   supplied `cluster` is used as-is and is **never stopped** by
#'   `power_sim()` -- the caller made it, the caller closes it.
#' @param parallel `"psock"` (default, cross-platform,
#'   `parallel::parLapply()`) or `"fork"` (Unix only,
#'   `parallel::mclapply()`; errors clearly on Windows rather than
#'   silently running sequentially). Only consulted when `workers > 1`
#'   or `cluster` is supplied.
#' @param clear_cache Logical, default `FALSE`. If `TRUE`, clears
#'   simtte's compiled-model cache (`simtte::simtte_model_cache_clear()`,
#'   current-version subdirectory only) after this call finishes, error
#'   or not -- never before the run, which would defeat the
#'   prepare/cache design by forcing every model to recompile. Useful to
#'   free disk space after a large one-off run; leave `FALSE` for
#'   repeated `power_sim()` calls in the same session, which benefit
#'   from the cache staying warm between them.
#'
#' @return A `"simttepower_result"` object: `$results`, one row per
#'   scenario x replicate x analysis (see `reports/01_phase1_plan.md`
#'   section 5 for the column list, plus `global_index`, the task's
#'   position in the flat scenario x replicate sequence -- what
#'   [power_sim_merge()] sorts a chunked run's results by), plus the
#'   grid, `n_sims`, `seed`, `reject`, and `alpha` used, for
#'   [summary.simttepower_result()].
#' @seealso [scenario_grid()], [summary.simttepower_result()],
#'   [plot_power()] for a power curve from that summary. For splitting a
#'   run across separate processes/a job scheduler instead of local
#'   `workers`: [power_sim_chunks()], [power_sim_chunk()],
#'   [power_sim_merge()].
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
#' res <- power_sim(grid, n_sims = 3, seed = 1, progress = FALSE)
#' res
#' summary(res)
#' }
#' @export
power_sim <- function(grid, n_sims, seed, reject = reject_default,
    alpha = 0.05, progress = interactive(), workers = 1, cluster = NULL,
    parallel = c("psock", "fork"), clear_cache = FALSE) {
    parallel <- match.arg(parallel)
    .validate_power_sim_args(grid, n_sims, seed)
    .validate_parallel_args(workers, cluster, parallel)
    if (!is.null(cluster)) {
        if (!missing(workers) && length(cluster) != workers) {
            message("`workers` (", workers, ") ignored; using `cluster`'s ",
                "own size (", length(cluster), ").")
        }
        workers <- length(cluster)
    }
    workers <- as.integer(workers)
    n_sims <- as.integer(n_sims)
    if (isTRUE(clear_cache)) {
        on.exit(simtte::simtte_model_cache_clear(), add = TRUE)
    }

    result_rows <- .with_rng_restored({
        task_table <- .build_task_table(grid, n_sims, seed)
        .dispatch_tasks(grid, task_table, workers, cluster, parallel, progress)
    })

    structure(list(results = .rbind_fill(result_rows), grid = grid,
        n_sims = n_sims, seed = seed, reject = reject, alpha = alpha,
        call = sys.call()), class = "simttepower_result")
}

# ---------------------------------------------------------------------
# Shared by power_sim() and power_sim_chunk() (R/power_sim_chunks.R):
# building the task table (global-index -> L'Ecuyer stream mapping) and
# dispatching it, sequentially or across local workers. Neither function
# knows or cares whether it is running the full grid or one chunk's own
# subset of it -- a task table row carries everything .run_task() needs.
# ---------------------------------------------------------------------

# Runs `expr` with the ambient RNG kind/state saved before and restored
# after, regardless of how `expr` mutates .Random.seed while running --
# every dispatched task reassigns .Random.seed directly, to a specific,
# already-derived stream value, well after this wrapper starts. Its own
# top-level "RNG session": power_sim() and power_sim_chunk() each use
# exactly one, wrapping everything from stream derivation through
# dispatch.
.with_rng_restored <- function(expr) {
    old_kind <- RNGkind()[1]
    has_old_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
    old_seed <- if (has_old_seed) get(".Random.seed", envir = .GlobalEnv) else NULL
    on.exit({
        # RNGkind() order matters: switching kind re-derives a fresh
        # .Random.seed for the new kind, so the kind switch must happen
        # BEFORE restoring the caller's own .Random.seed value, or the
        # switch would immediately overwrite it again.
        suppressWarnings(RNGkind(old_kind))
        if (has_old_seed) {
            assign(".Random.seed", old_seed, envir = .GlobalEnv)
        } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
            rm(".Random.seed", envir = .GlobalEnv)
        }
    })
    expr
}

# The full (scenario x replicate) task table for `grid`/`n_sims`/`seed`:
# one row per task, with its global index and precomputed L'Ecuyer-CMRG
# RNG stream already attached. A pure function of (grid shape, n_sims,
# seed) -- never of worker id, dispatch order, or how the caller later
# subsets these rows (power_sim_chunk() calls this with the *same*
# n_sims/seed as the full run, then keeps only its own chunk's rows, so
# a replicate's stream never depends on how the run was chunked; see
# reports/07_phase3_design.md). Must run inside .with_rng_restored() --
# it switches RNGkind()/seeds the ambient RNG as a side effect and
# leaves that switch in place for the caller's own dispatch loop to use.
.build_task_table <- function(grid, n_sims, seed) {
    n_scn <- nrow(grid)
    n_tasks <- n_scn * n_sims
    task_table <- data.frame(
        scenario_row = rep(seq_len(n_scn), each = n_sims),
        replicate = rep(seq_len(n_sims), times = n_scn))
    # Global-index -> RNG-stream mapping: a pure function of (scenario,
    # replicate) identity, never of worker id or dispatch order -- the
    # one invariant Phase 2/3 rely on (reports/01_phase1_plan.md section 5).
    task_table$global_index <- (task_table$scenario_row - 1L) * n_sims +
        task_table$replicate

    RNGkind("L'Ecuyer-CMRG")
    set.seed(seed)
    s <- get(".Random.seed", envir = .GlobalEnv)
    streams <- vector("list", n_tasks)
    for (i in seq_len(n_tasks)) {
        streams[[i]] <- s
        s <- parallel::nextRNGStream(s)
    }
    task_table$stream <- streams[task_table$global_index]
    task_table
}

# Runs every row of `task_table` (the full table, or any subset of it --
# power_sim_chunk() passes a chunk's own rows here unchanged) and returns
# the list of per-task result-row data frames, sequentially or across
# local workers exactly as power_sim() always has.
.dispatch_tasks <- function(grid, task_table, workers, cluster, parallel,
    progress) {
    n_tasks <- nrow(task_table)
    if (workers <= 1L) {
        # The Phase 1 path, unchanged: no cluster, no worker-setup code.
        if (isTRUE(progress)) {
            pb <- utils::txtProgressBar(min = 0, max = n_tasks, style = 3)
            on.exit(close(pb), add = TRUE)
        }
        result_rows <- vector("list", n_tasks)
        for (i in seq_len(n_tasks)) {
            assign(".Random.seed", task_table$stream[[i]], envir = .GlobalEnv)
            result_rows[[i]] <- .run_task(grid, task_table[i, ])
            if (isTRUE(progress)) utils::setTxtProgressBar(pb, i)
        }
        result_rows
    } else {
        .run_tasks_parallel(grid, task_table, workers, cluster, parallel,
            progress)
    }
}

.validate_power_sim_args <- function(grid, n_sims, seed) {
    if (!inherits(grid, "simttepower_scenario_grid")) {
        stop("`grid` must be a scenario_grid() object.", call. = FALSE)
    }
    if (!is.numeric(n_sims) || length(n_sims) != 1L || n_sims < 1 ||
        n_sims != round(n_sims)) {
        stop("`n_sims` must be a single positive whole number.", call. = FALSE)
    }
    if (!is.numeric(seed) || length(seed) != 1L) {
        stop("`seed` must be a single number.", call. = FALSE)
    }
}

.validate_parallel_args <- function(workers, cluster, parallel) {
    if (!is.null(cluster) && !inherits(cluster, "cluster")) {
        stop("`cluster` must be a parallel cluster object (from ",
            "parallel::makeCluster()/makePSOCKcluster()), or NULL.",
            call. = FALSE)
    }
    if (is.null(cluster) &&
        (!is.numeric(workers) || length(workers) != 1L || workers < 1 ||
            workers != round(workers))) {
        stop("`workers` must be a single positive whole number.",
            call. = FALSE)
    }
    if (identical(parallel, "fork") && .Platform$OS.type != "unix") {
        stop("parallel = \"fork\" is not supported on Windows; use ",
            "parallel = \"psock\" (the default).", call. = FALSE)
    }
}

# ---------------------------------------------------------------------
# Phase 2: local parallel dispatch (reports/04_phase2_design.md). The
# task table (with each row's own precomputed L'Ecuyer stream already
# attached) and .run_task() are exactly what Phase 1 built; only how
# .run_task() gets invoked differs here.
# ---------------------------------------------------------------------

.run_tasks_parallel <- function(grid, task_table, workers, cluster,
    parallel, progress) {
    n_tasks <- nrow(task_table)
    tasks <- lapply(seq_len(n_tasks), function(i) task_table[i, ])
    mode_label <- if (identical(parallel, "fork")) "fork" else "PSOCK"
    if (isTRUE(progress)) {
        message(sprintf("Running %d tasks on %d workers (%s)...", n_tasks,
            workers, mode_label))
    }

    # Pre-flight: build/validate every distinct model in `grid` once, in
    # this (parent) process, via simtte::simtte_prepare_model() -- the
    # supported replacement for simttepower's own former direct
    # mrgsolve::mcode_cache()/loadso() calls and retry loop (see
    # ../simtte/reports/30_simttepower_feedback_worker_loading.md). A
    # model that cannot build (bad tte_model() code, a missing mspline
    # `knots`, ...) errors here, once, naming the model -- not
    # per-replicate, discovered 300 rows into a run. Runs in both
    # dispatch modes, before any worker starts.
    prep <- tryCatch(.prepare_models(grid),
        error = function(e) {
            stop("power_sim(): preparing model(s) failed: ",
                conditionMessage(e), call. = FALSE)
        })
    grid <- prep$grid

    if (identical(parallel, "fork")) {
        # A forked worker inherits the parent process's memory --
        # including every model .prepare_models() just built and
        # loadso()'d above -- directly via copy-on-write. No per-worker
        # preparation step is needed, or possible (mrgsolve's own docs;
        # confirmed by simtte's own race investigation, cited above).
        raw <- tryCatch(
            parallel::mclapply(tasks, .run_task_worker, grid = grid,
                mc.cores = workers),
            error = function(e) {
                stop("power_sim(): parallel dispatch (fork) failed: ",
                    conditionMessage(e), ". Try workers = 1 to reproduce ",
                    "sequentially.", call. = FALSE)
            })
    } else {
        owns_cluster <- is.null(cluster)
        cl <- if (owns_cluster) parallel::makePSOCKcluster(workers) else cluster
        if (owns_cluster) {
            on.exit(parallel::stopCluster(cl), add = TRUE)
        }
        raw <- tryCatch({
            # library(simttepower), not a clusterExport() of individual
            # internal helper names: a scenario's analysis functions are
            # arbitrary user closures (trial_design(analyses = )), not
            # just this package's own two built-ins, so only a real
            # namespace load lets every such closure's own lexical
            # scoping resolve correctly on the worker -- exporting a
            # fixed helper list would both under-cover user closures and
            # be one more thing to keep in sync with this file's own
            # call graph.
            parallel::clusterCall(cl, library, "simttepower",
                character.only = TRUE)
            # Broadcast each already-prepared (built + loadso()'d) model
            # object to every worker -- a worker only ever loadso()s an
            # object it already has, never rebuilds, which is why this
            # is race-free by construction rather than by retrying
            # (simtte's own investigation, cited above: 0/15 failures
            # for this pattern vs. 6/15 for a worker reconstructing from
            # source against a shared directory). `grid` itself,
            # containing the same prepared objects, is then passed
            # straight to parLapply() -- parallel::parLapply() chunks
            # `tasks` across workers and serializes each chunk's fixed
            # `...` arguments (here, `grid`) once per worker, not once
            # per task, so this needs no separate clusterExport().
            for (p in prep$prepared) {
                parallel::clusterCall(cl, simtte::simtte_prepare_model,
                    model = p)
            }
            parallel::parLapply(cl, tasks, .run_task_worker, grid = grid)
        }, error = function(e) {
            stop("power_sim(): parallel dispatch (PSOCK) failed: ",
                conditionMessage(e), ". Try workers = 1 to reproduce ",
                "sequentially.", call. = FALSE)
        })
    }

    if (isTRUE(progress)) message("done.")
    .handle_worker_failures(raw, grid, task_table)
}

# One task on a worker: restore its assigned RNG stream, then run
# exactly the same .run_task() the sequential path uses. No model
# reconstruction here any more -- every arm's `model` field already
# carries the prepared object .prepare_models() built in the parent
# (see .run_tasks_parallel()); a worker only ever loadso()s it.
.run_task_worker <- function(task_row, grid) {
    assign(".Random.seed", task_row$stream[[1]], envir = .GlobalEnv)
    .run_task(grid, task_row)
}

# Builds/validates every distinct model in `grid` once, via
# simtte::simtte_prepare_model() -- see .run_tasks_parallel() for why.
# Returns the grid with every arm's `model` field replaced by its
# prepared object (built in this process), plus that same set of
# prepared objects keyed for the PSOCK broadcast step. mspline is the
# one model needing an extra argument at prepare time (`knots` --
# `coefs`/`boundary_knots` are not accepted by simtte_prepare_model();
# they still go to sim_tte_ode() as usual via arm()'s own `...`).
.prepare_models <- function(grid) {
    keyed <- list()
    for (scn in grid$scenario) {
        for (a in scn$design$arms) {
            key <- .model_key(a)
            if (is.null(keyed[[key]])) keyed[[key]] <- a
        }
    }
    prepared <- lapply(keyed, function(a) {
        if (identical(a$model, "mspline")) {
            simtte::simtte_prepare_model(model = a$model, knots = a$knots)
        } else {
            simtte::simtte_prepare_model(model = a$model)
        }
    })
    grid$scenario <- lapply(grid$scenario, function(scn) {
        scn$design$arms <- lapply(scn$design$arms, function(a) {
            a$model <- prepared[[.model_key(a)]]
            a
        })
        scn
    })
    list(grid = grid, prepared = prepared)
}

.model_key <- function(a) {
    if (inherits(a$model, "simtte_model")) {
        paste0("tte_model:", a$model$name)
    } else if (identical(a$model, "mspline")) {
        paste0("mspline:", length(a$knots))
    } else {
        paste0("builtin:", a$model)
    }
}

# mclapply() localizes a forked job's own crash to a try-error placeholder
# for that job only (not raised to the caller); parLapply()'s own
# dispatch-level failures are already caught by .run_tasks_parallel()'s
# tryCatch above. Any try-error element here is therefore a worker
# *process* failure, not a captured replicate error -- turned into an
# explicit, distinctly-worded error row (via the same .error_rows()
# .run_task() itself uses for a simulation failure) rather than crashing
# the combine step or silently vanishing from the results.
.handle_worker_failures <- function(raw, grid, task_table) {
    lapply(seq_along(raw), function(i) {
        r <- raw[[i]]
        if (inherits(r, "try-error")) {
            cond <- attr(r, "condition")
            msg <- paste0("worker process failed: ",
                if (!is.null(cond)) conditionMessage(cond) else "unknown error")
            .error_rows(grid, task_table[i, ], msg)
        } else {
            r
        }
    })
}

# One error row per analysis configured for this scenario -- shared by
# .run_task()'s own simulation-failure branch and .handle_worker_failures()'s
# worker-crash branch, the only two places a task never got far enough to
# run any analysis at all.
.error_rows <- function(grid, task_row, msg, runtime = NA_real_) {
    scn <- grid$scenario[[task_row$scenario_row]]
    scn_cols <- grid[task_row$scenario_row,
        setdiff(names(grid), "scenario"), drop = FALSE]
    rows <- lapply(names(scn$design$analyses), function(nm) {
        .result_row(scn_cols, task_row$replicate, nm, c(error = msg), runtime,
            task_row$global_index)
    })
    .rbind_fill(rows)
}

# The per-item runner: (grid, one task-table row) -> its result rows.
# Pure given the ambient RNG stream already positioned by the caller; no
# shared mutable state and no assumption about call order -- exactly the
# unit Phase 2/3 redistribute across workers/chunks unchanged
# (reports/01_phase1_plan.md section 7).
.run_task <- function(grid, task_row) {
    scn <- grid$scenario[[task_row$scenario_row]]
    t0 <- proc.time()[["elapsed"]]
    sim <- tryCatch(
        list(events = .simulate_scenario(scn$design), error = NA_character_),
        error = function(e) list(events = NULL, error = conditionMessage(e)))
    runtime <- unname(proc.time()[["elapsed"]] - t0)

    if (!is.na(sim$error)) {
        return(.error_rows(grid, task_row, sim$error, runtime))
    }

    scn_cols <- grid[task_row$scenario_row,
        setdiff(names(grid), "scenario"), drop = FALSE]
    # Expected events/duration: cheap, already available from `events`
    # regardless of which analysis runs, so every replicate gets them
    # (reports/01_phase1_plan.md section 4) -- attached to every
    # analysis's own row for that replicate, same convention the
    # postcard used for its own per-row `runtime_sec`.
    event_summary <- .event_summary(sim$events)

    rows <- lapply(names(scn$design$analyses), function(nm) {
        out <- tryCatch(scn$design$analyses[[nm]](sim$events),
            error = function(e) c(error = conditionMessage(e)))
        row <- .result_row(scn_cols, task_row$replicate, nm, out, runtime,
            task_row$global_index)
        for (cn in names(event_summary)) row[[cn]] <- event_summary[[cn]]
        row
    })
    .rbind_fill(rows)
}

.event_summary <- function(events) {
    counts <- tapply(events$sim_status, events$arm, sum)
    out <- stats::setNames(as.list(as.numeric(counts)),
        paste0("n_events_", names(counts)))
    c(out, list(duration = max(events$sim_time, na.rm = TRUE)))
}

.result_row <- function(scn_cols, replicate, analysis_name, out, runtime,
    global_index = NA_integer_) {
    err <- NA_character_
    if (!is.null(names(out)) && "error" %in% names(out)) {
        err <- unname(out[["error"]])
        out <- out[setdiff(names(out), "error")]
    }
    extra <- if (length(out)) {
        as.data.frame(as.list(out), stringsAsFactors = FALSE,
            check.names = FALSE)
    } else {
        data.frame(matrix(ncol = 0, nrow = 1))
    }
    cbind(scn_cols,
        data.frame(replicate = replicate, analysis = analysis_name,
            stringsAsFactors = FALSE),
        extra,
        data.frame(error = err, runtime_sec = runtime,
            global_index = global_index, stringsAsFactors = FALSE))
}

# Simulates every arm of a resolved design (do.call(sim_tte_ode, ...) per
# arm -- confirmed to need no simtte change, reports/00_simtte_api.md),
# then joins arm/regimen/dose/covariates labels onto the combined events
# (reports/01_phase1_plan.md addendum, "Estimand scope and group
# labels"). No cum_dose: dropped after Phase 1 (reports/02_author_decisions.md,
# "After Phase 1" decision 2) -- wrong for addl/ii regimens (one row
# with addl = 11 counted as one dose) and not needed (groups are the
# arm/regimen labels; a numeric contrast exists only when the user
# declares `dose`).
.simulate_scenario <- function(design) {
    arm_labels <- vapply(design$arms, `[[`, "", "label")
    regimen_labels <- unique(vapply(design$arms, `[[`, "", "regimen"))

    parts <- lapply(design$arms, function(a) {
        call_args <- a[intersect(names(a), .sim_tte_ode_arg_names)]
        if (is.null(call_args$end)) call_args$end <- design$end
        if (is.null(call_args$end)) {
            stop("Arm '", a$label, "' has no `end`, and the trial_design ",
                "has none either -- set one of the two.", call. = FALSE)
        }
        sim_out <- suppressMessages(do.call(simtte::sim_tte_ode, call_args))
        .label_arm_events(a, sim_out)
    })
    events <- .rbind_fill(parts)
    events$arm <- factor(events$arm, levels = arm_labels)
    events$regimen <- factor(events$regimen, levels = regimen_labels)
    events
}

.label_arm_events <- function(a, sim_out) {
    ev <- sim_out$events
    ev$arm <- a$label
    ev$regimen <- a$regimen
    if (!is.null(a$dose)) ev$dose <- a$dose
    if (!is.null(a$covariates) && is.data.frame(a$covariates)) {
        cov <- a$covariates
        if ("time" %in% names(cov)) {
            # Time-varying covariates are joined at baseline only (first
            # row per ID) -- documented, not a full time-varying join.
            cov <- cov[order(cov$ID, cov$time), ]
            cov <- cov[!duplicated(cov$ID), setdiff(names(cov), "time"),
                drop = FALSE]
        }
        ev <- merge(ev, cov, by = "ID", all.x = TRUE, sort = FALSE)
    }
    ev$subject_id <- paste(a$label, ev$ID, sep = "_")
    ev
}

#' @export
print.simttepower_result <- function(x, ...) {
    n_scn <- nrow(x$grid)
    n_err <- sum(!is.na(x$results$error))
    cat(sprintf(
        "<simttepower_result> %d scenario(s) x %d replicate(s) x %d analysis(es)\n",
        n_scn, x$n_sims, length(unique(x$results$analysis))))
    cat(sprintf("  seed: %s\n", format(x$seed)))
    cat(sprintf("  errors: %d / %d replicate-analyses\n", n_err,
        nrow(x$results)))
    invisible(x)
}
