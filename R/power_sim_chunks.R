#' Split a power_sim() run into independent chunks
#'
#' `power_sim_chunks()`/[power_sim_chunk()]/[power_sim_merge()] let a
#' `power_sim()` run execute as separate processes -- on a job scheduler
#' (SGE, Slurm, any array job; see `inst/templates/`), or just
#' sequentially on one machine -- and merge their results into the same
#' object a single `power_sim()` call would have produced, byte-identical
#' for the same seed (`reports/07_phase3_design.md`). No scheduler
#' dependency: plain files (`manifest.rds` plus one `chunk_<i>.rds` per
#' chunk) are the entire mechanism.
#'
#' `power_sim_chunks()` itself runs no simulation -- it only partitions
#' the flat (scenario x replicate) task list into `n_chunks` contiguous
#' ranges and writes a manifest recording everything [power_sim_chunk()]
#' and [power_sim_merge()] need. Reproducibility across chunking is the
#' key invariant: replicate `k` of scenario `s`'s L'Ecuyer-CMRG stream
#' depends only on `(s, k, n_sims, seed)`, never on `n_chunks` or
#' execution order -- see [power_sim_chunk()].
#'
#' The two shell scripts in `inst/templates/` (SGE and Slurm array jobs)
#' are examples to copy and adapt for your own scheduler/queue/account
#' settings -- they are not executed by simttepower or its own tests (no
#' CRAN check machine has a scheduler to run them against), and are
#' reviewed by hand, not by a test. The tested contract is these three R
#' functions, which the scripts only ever call.
#'
#' @param grid A `simttepower_scenario_grid` (see [scenario_grid()]).
#' @param n_sims Replicates per scenario. Same meaning as [power_sim()]'s
#'   own `n_sims`.
#' @param seed A single base seed. Same meaning as [power_sim()]'s own
#'   `seed`.
#' @param reject,alpha Stored on the manifest and later on the merged
#'   result, same as [power_sim()]'s own `reject`/`alpha`.
#' @param n_chunks Number of chunks to split the run into. A positive
#'   whole number, at most the total task count (`nrow(grid) * n_sims`).
#' @param dir Directory to write the manifest into. Created if it
#'   doesn't exist.
#'
#' @return The manifest, invisibly.
#' @seealso [power_sim_chunk()], [power_sim_merge()], [power_sim()],
#'   [scenario_grid()]
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
#'
#' dir <- tempfile()
#' power_sim_chunks(grid, n_sims = 6, seed = 1, n_chunks = 2, dir = dir)
#' power_sim_chunk(dir, 1, progress = FALSE)
#' power_sim_chunk(dir, 2, progress = FALSE)
#' res <- power_sim_merge(dir)
#' res
#' }
#' @export
power_sim_chunks <- function(grid, n_sims, seed, reject = reject_default,
    alpha = 0.05, n_chunks, dir) {
    .validate_power_sim_args(grid, n_sims, seed)
    if (!is.numeric(n_chunks) || length(n_chunks) != 1L || n_chunks < 1 ||
        n_chunks != round(n_chunks)) {
        stop("`n_chunks` must be a single positive whole number.",
            call. = FALSE)
    }
    n_chunks <- as.integer(n_chunks)
    n_sims <- as.integer(n_sims)
    n_tasks <- nrow(grid) * n_sims
    if (n_chunks > n_tasks) {
        stop("`n_chunks` (", n_chunks, ") exceeds the number of tasks (",
            n_tasks, ": ", nrow(grid), " scenario(s) x ", n_sims,
            " replicate(s)).", call. = FALSE)
    }
    if (!dir.exists(dir)) dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    if (!dir.exists(dir)) {
        stop("Could not create `dir`: ", dir, call. = FALSE)
    }

    manifest <- list(
        format_version = 1L,
        simttepower_version = as.character(utils::packageVersion("simttepower")),
        simtte_version = as.character(utils::packageVersion("simtte")),
        r_version = as.character(getRversion()),
        grid = grid, n_sims = n_sims, seed = seed, reject = reject,
        alpha = alpha, n_tasks = n_tasks, n_chunks = n_chunks,
        bounds = .chunk_bounds(n_tasks, n_chunks),
        grid_hash = .grid_fingerprint(grid))

    saveRDS(manifest, file.path(dir, "manifest.rds"))
    writeLines(.manifest_summary(manifest), file.path(dir, "manifest.txt"))
    invisible(manifest)
}

#' Run one chunk of a power_sim_chunks() run
#'
#' Reads the manifest [power_sim_chunks()] wrote to `dir`, runs chunk
#' `i`'s own share of the (scenario x replicate) task list, and writes
#' `chunk_<i>.rds` into `dir`. This is what one job-array task calls
#' (see `inst/templates/`); it can also just be called in a loop on one
#' machine.
#'
#' **Reproducibility across chunking**: this rebuilds the *entire*
#' (scenario x replicate) task table via the same stream-derivation
#' `power_sim()` itself uses (`n_sims`/`seed` come from the manifest, not
#' from `i` or `dir`), then keeps only the rows chunk `i` owns. A
#' replicate's L'Ecuyer-CMRG stream is therefore a pure function of its
#' `(scenario, replicate)` identity alone -- never of `i`, `n_chunks`, or
#' when/where this chunk happened to run (`reports/07_phase3_design.md`
#' section 2, 6).
#'
#' @param dir The directory [power_sim_chunks()] wrote its manifest into.
#' @param i Which chunk to run: a whole number from 1 to this manifest's
#'   own `n_chunks`.
#' @param workers,cluster,parallel Local parallelism *within this chunk*
#'   only -- independent of `n_chunks`; see [power_sim()]'s own
#'   arguments of the same name. Never more than 2 `workers` in a test or
#'   example (CRAN policy).
#' @param progress Show progress for this chunk. Default `interactive()`.
#' @param clear_cache Passed to the same effect as [power_sim()]'s own
#'   `clear_cache` -- clears simtte's compiled-model cache (current
#'   version subdirectory only) after this chunk finishes, error or not.
#'   Default `FALSE`; a real array-job task is normally enough of a
#'   one-off that `TRUE` is reasonable there too. If `cache_dir` is also
#'   given, the clear targets *that* directory (fires before the option
#'   is restored), not whatever `simtte.cache_dir` was set to before this
#'   call.
#' @param cache_dir A directory to point `options(simtte.cache_dir = )`
#'   at for the duration of this call only -- equivalent to the caller
#'   setting that option themselves before calling `power_sim_chunk()`,
#'   offered because a scheduler array script often can't easily set an R
#'   option before its own `Rscript -e` invocation. `NULL` (default):
#'   leaves the option exactly as found. Never left changed after this
#'   call returns, error or not -- no new state outlives the call, and
#'   [power_sim()] does not get this argument since a single interactive
#'   call can already set the option directly.
#'
#' @return The chunk's own result (a list with `chunk`, `results`, and a
#'   version/grid fingerprint for [power_sim_merge()]'s own consistency
#'   check), invisibly. The interesting side effect is the file it wrote.
#' @seealso [power_sim_chunks()], [power_sim_merge()], [power_sim()]
#' @examples
#' \donttest{
#' design <- trial_design(
#'   arms = list(
#'     arm(label = "comparator", n = 20, model = "irm1_hazard", end = 24,
#'       param = list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5,
#'         IC50 = 1, IMAX = 0.9, H0 = 0.15)),
#'     arm(label = "experimental", n = 20, model = "irm1_hazard", end = 24,
#'       param = list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5,
#'         IC50 = 3, IMAX = 0.9, H0 = 0.15))),
#'   analyses = list(coxph = analysis_coxph))
#' grid <- scenario_grid(design, over = list(arm = "experimental",
#'   field = "n", values = c(20, 40)))
#'
#' dir <- tempfile()
#' power_sim_chunks(grid, n_sims = 4, seed = 1, n_chunks = 2, dir = dir)
#' power_sim_chunk(dir, 1, progress = FALSE)
#' power_sim_chunk(dir, 2, progress = FALSE)
#' }
#' @export
power_sim_chunk <- function(dir, i, workers = 1, cluster = NULL,
    parallel = c("psock", "fork"), progress = interactive(),
    clear_cache = FALSE, cache_dir = NULL) {
    parallel <- match.arg(parallel)
    manifest <- .read_manifest(dir)
    .validate_chunk_index(manifest, i)
    i <- as.integer(i)
    .validate_parallel_args(workers, cluster, parallel)
    if (!is.null(cluster)) workers <- length(cluster)
    workers <- as.integer(workers)

    if (!is.null(cache_dir)) {
        old_cache_opt <- options(simtte.cache_dir = cache_dir)
    }
    # Registered in this order deliberately: a clear (if requested) must
    # run *before* cache_dir's own option restore, so it clears the
    # directory this call actually used, not whatever was set before it.
    # on.exit(..., add = TRUE) runs handlers in registration order, not
    # last-in-first-out.
    if (isTRUE(clear_cache)) {
        on.exit(simtte::simtte_model_cache_clear(), add = TRUE)
    }
    if (!is.null(cache_dir)) {
        on.exit(options(old_cache_opt), add = TRUE)
    }

    bounds <- manifest$bounds[manifest$bounds$chunk == i, ]
    result_rows <- .with_rng_restored({
        task_table <- .build_task_table(manifest$grid, manifest$n_sims,
            manifest$seed)
        chunk_table <- task_table[
            task_table$global_index >= bounds$start &
                task_table$global_index <= bounds$end, ]
        .dispatch_tasks(manifest$grid, chunk_table, workers, cluster,
            parallel, progress)
    })

    out <- list(chunk = i, grid_hash = manifest$grid_hash,
        simttepower_version = as.character(utils::packageVersion("simttepower")),
        simtte_version = as.character(utils::packageVersion("simtte")),
        r_version = as.character(getRversion()),
        results = .rbind_fill(result_rows))
    saveRDS(out, file.path(dir, .chunk_filename(i, manifest$n_chunks)))
    invisible(out)
}

#' Merge power_sim_chunk() output into one power_sim() result
#'
#' Reads the manifest and every present `chunk_<i>.rds` in `dir`,
#' combines them, and returns the same `simttepower_result` a single
#' `power_sim()` call (with the same `grid`/`n_sims`/`seed`) would have
#' produced -- byte-identical, excluding `runtime_sec`, regardless of
#' `n_chunks` or the order chunks ran in.
#'
#' @param dir The directory [power_sim_chunks()] wrote its manifest into,
#'   with one or more `chunk_<i>.rds` files from [power_sim_chunk()].
#' @param partial If `FALSE` (default), a missing chunk file errors,
#'   naming which chunk(s) are missing. If `TRUE`, merges whatever chunk
#'   files are present and returns a result covering only those rows --
#'   the caller is accepting the gap.
#'
#' @return A `simttepower_result`, the same class [power_sim()] returns.
#' @seealso [power_sim_chunks()], [power_sim_chunk()], [power_sim()],
#'   [summary.simttepower_result()]
#' @examples
#' \donttest{
#' design <- trial_design(
#'   arms = list(
#'     arm(label = "comparator", n = 20, model = "irm1_hazard", end = 24,
#'       param = list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5,
#'         IC50 = 1, IMAX = 0.9, H0 = 0.15)),
#'     arm(label = "experimental", n = 20, model = "irm1_hazard", end = 24,
#'       param = list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5,
#'         IC50 = 3, IMAX = 0.9, H0 = 0.15))),
#'   analyses = list(coxph = analysis_coxph))
#' grid <- scenario_grid(design, over = list(arm = "experimental",
#'   field = "n", values = c(20, 40)))
#'
#' dir <- tempfile()
#' power_sim_chunks(grid, n_sims = 4, seed = 1, n_chunks = 2, dir = dir)
#' power_sim_chunk(dir, 1, progress = FALSE)
#' power_sim_chunk(dir, 2, progress = FALSE)
#' res <- power_sim_merge(dir)
#' summary(res)
#' }
#' @export
power_sim_merge <- function(dir, partial = FALSE) {
    manifest <- .read_manifest(dir)
    files <- vapply(seq_len(manifest$n_chunks),
        function(i) .chunk_filename(i, manifest$n_chunks), "")
    present <- file.exists(file.path(dir, files))
    missing_idx <- which(!present)

    if (length(missing_idx) && !isTRUE(partial)) {
        stop("power_sim_merge(): missing chunk file(s) for chunk(s) ",
            paste(missing_idx, collapse = ", "), " in '", dir, "'. Run ",
            "power_sim_chunk() for the missing chunk(s), or pass ",
            "partial = TRUE to merge what is present.", call. = FALSE)
    }

    chunks <- lapply(file.path(dir, files[present]), readRDS)
    for (ch in chunks) {
        if (!identical(ch$grid_hash, manifest$grid_hash)) {
            stop("power_sim_merge(): chunk ", ch$chunk, "'s grid does not ",
                "match this manifest's grid (a stale or mismatched chunk ",
                "file) -- re-run power_sim_chunks()/power_sim_chunk() for ",
                "this directory.", call. = FALSE)
        }
        .check_chunk_versions(ch, manifest)
    }

    results <- .rbind_fill(lapply(chunks, `[[`, "results"))
    results <- results[order(results$global_index), , drop = FALSE]
    rownames(results) <- NULL

    structure(list(results = results, grid = manifest$grid,
        n_sims = manifest$n_sims, seed = manifest$seed,
        reject = manifest$reject, alpha = manifest$alpha,
        call = sys.call()), class = "simttepower_result")
}

# ---------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------

# Partitions 1:n_tasks into n_chunks contiguous ranges of near-equal
# size (sizes differ by at most 1) -- no gap, no overlap, by
# construction: a sizes vector summing to n_tasks, cumsum()'d into ends.
.chunk_bounds <- function(n_tasks, n_chunks) {
    base <- n_tasks %/% n_chunks
    extra <- n_tasks %% n_chunks
    sizes <- rep(base, n_chunks) + c(rep(1L, extra), rep(0L, n_chunks - extra))
    ends <- cumsum(sizes)
    data.frame(chunk = seq_len(n_chunks), start = ends - sizes + 1L, end = ends)
}

# A lightweight content fingerprint for a grid, not a cryptographic hash
# -- it only needs to catch "this chunk file came from a different
# grid/run", not resist tampering, so a real MD5 (via tools::md5sum(),
# already shipped with every R installation -- no new dependency) on the
# grid's own serialized bytes is simple and sufficient.
.grid_fingerprint <- function(grid) {
    f <- tempfile()
    on.exit(unlink(f))
    saveRDS(grid, f)
    unname(tools::md5sum(f))
}

.chunk_filename <- function(i, n_chunks) {
    width <- max(3L, nchar(as.character(n_chunks)))
    sprintf(paste0("chunk_%0", width, "d.rds"), i)
}

.read_manifest <- function(dir) {
    f <- file.path(dir, "manifest.rds")
    if (!file.exists(f)) {
        stop("No manifest.rds found in '", dir, "' -- run ",
            "power_sim_chunks() first.", call. = FALSE)
    }
    readRDS(f)
}

.validate_chunk_index <- function(manifest, i) {
    if (!is.numeric(i) || length(i) != 1L || i != round(i) ||
        i < 1 || i > manifest$n_chunks) {
        stop("`i` must be a single whole number between 1 and ",
            manifest$n_chunks, " (this manifest has ", manifest$n_chunks,
            " chunks).", call. = FALSE)
    }
}

# A chunk file that disagrees with the manifest on which
# simttepower/simtte/R version generated it isn't necessarily wrong --
# but silently combining chunks built under different versions of the
# actual simulator can bake in a version-dependent difference no RNG
# invariant protects against. Warns (not errors): unlike a grid
# mismatch, this is not proof of a wrong merge, only a reason to check.
.check_chunk_versions <- function(chunk, manifest) {
    fields <- c("simttepower_version", "simtte_version", "r_version")
    mismatched <- fields[vapply(fields, function(f) {
        !identical(chunk[[f]], manifest[[f]])
    }, logical(1))]
    if (length(mismatched)) {
        warning("power_sim_merge(): chunk ", chunk$chunk, " was generated ",
            "under different ", paste(mismatched, collapse = "/"),
            " than this manifest's own version metadata records -- ",
            "results may not be directly comparable.", call. = FALSE)
    }
}

# A short, human-readable companion to manifest.rds -- for someone
# inspecting `dir` without starting R (e.g. before submitting an array
# job).
.manifest_summary <- function(manifest) {
    c(
        sprintf("simttepower chunk manifest (format version %d)",
            manifest$format_version),
        sprintf("  simttepower %s, simtte %s, R %s",
            manifest$simttepower_version, manifest$simtte_version,
            manifest$r_version),
        sprintf("  seed: %s", format(manifest$seed)),
        sprintf("  scenarios: %d, n_sims: %d, tasks: %d",
            nrow(manifest$grid), manifest$n_sims, manifest$n_tasks),
        sprintf("  chunks: %d", manifest$n_chunks),
        "  chunk  start  end",
        sprintf("  %5d  %5d  %5d", manifest$bounds$chunk,
            manifest$bounds$start, manifest$bounds$end),
        "",
        "Run power_sim_chunk(dir, i) for each chunk (1..n_chunks), then",
        "power_sim_merge(dir) once every chunk_<i>.rds is present.")
}
