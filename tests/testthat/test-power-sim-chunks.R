# Phase 3: power_sim_chunks()/power_sim_chunk()/power_sim_merge(). Fast
# tests here are manifest bookkeeping and error paths only, using a small
# synthetic set of chunk files rather than real simulation (that needs
# real chunk runs -- slow, below). All file I/O goes to tempfile(), never
# a real cache or cwd.

test_that("power_sim_chunks() writes a manifest with the right chunk count", {
    dir <- tempfile()
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1, 2)))
    manifest <- power_sim_chunks(g, n_sims = 5, seed = 1, n_chunks = 3,
        dir = dir)
    expect_true(file.exists(file.path(dir, "manifest.rds")))
    expect_true(file.exists(file.path(dir, "manifest.txt")))
    expect_identical(manifest$n_chunks, 3L)
    expect_identical(manifest$n_tasks, 10L)  # 2 scenarios x 5 replicates
    expect_identical(nrow(manifest$bounds), 3L)
})

test_that("power_sim_chunks() validates n_chunks", {
    dir <- tempfile()
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    expect_error(power_sim_chunks(g, n_sims = 2, seed = 1, n_chunks = 0,
        dir = dir), "positive whole number")
    expect_error(power_sim_chunks(g, n_sims = 2, seed = 1, n_chunks = 1.5,
        dir = dir), "positive whole number")
    expect_error(power_sim_chunks(g, n_sims = 2, seed = 1, n_chunks = 100,
        dir = dir), "exceeds the number of tasks")
})

test_that(".chunk_bounds() partitions with no gap and no overlap", {
    specs <- list(c(10L, 1L), c(10L, 10L), c(10L, 3L), c(17L, 5L), c(1L, 1L))
    for (spec in specs) {
        n_tasks <- spec[1]; n_chunks <- spec[2]
        b <- simttepower:::.chunk_bounds(n_tasks, n_chunks)
        expect_identical(nrow(b), n_chunks)
        expect_identical(b$start[1], 1L)
        expect_identical(b$end[n_chunks], n_tasks)
        # No gap: each chunk's start is the previous chunk's end + 1.
        if (n_chunks > 1) {
            expect_identical(b$start[-1], b$end[-n_chunks] + 1L)
        }
        # No overlap, exact partition: sizes sum to n_tasks.
        expect_identical(sum(b$end - b$start + 1L), n_tasks)
    }
})

test_that("power_sim_merge() returns the right shape for a complete chunk set", {
    dir <- tempfile()
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    manifest <- power_sim_chunks(g, n_sims = 4, seed = 1, n_chunks = 2,
        dir = dir)

    # Synthetic chunk files -- exercises power_sim_merge()'s own
    # bookkeeping without a real simulation run.
    for (i in 1:2) {
        b <- manifest$bounds[manifest$bounds$chunk == i, ]
        rows <- lapply(b$start:b$end, function(gi) {
            data.frame(scenario_id = "s1", replicate = gi, analysis = "x",
                error = NA_character_, runtime_sec = 0.01,
                global_index = gi, stringsAsFactors = FALSE)
        })
        out <- list(chunk = i, grid_hash = manifest$grid_hash,
            simttepower_version = manifest$simttepower_version,
            simtte_version = manifest$simtte_version,
            r_version = manifest$r_version,
            results = do.call(rbind, rows))
        saveRDS(out, file.path(dir, simttepower:::.chunk_filename(i, 2)))
    }

    res <- power_sim_merge(dir)
    expect_s3_class(res, "simttepower_result")
    expect_identical(nrow(res$results), 4L)
    expect_identical(res$results$global_index, 1:4)  # sorted
    expect_identical(res$n_sims, 4L)
    expect_identical(res$seed, 1)
})

test_that("power_sim_merge() errors and names a missing chunk", {
    dir <- tempfile()
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    power_sim_chunks(g, n_sims = 2, seed = 1, n_chunks = 2, dir = dir)
    expect_error(power_sim_merge(dir), "missing chunk file\\(s\\) for chunk\\(s\\) 1, 2")
})

test_that("power_sim_merge(partial = TRUE) merges what is present", {
    dir <- tempfile()
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    manifest <- power_sim_chunks(g, n_sims = 4, seed = 1, n_chunks = 2,
        dir = dir)
    b <- manifest$bounds[manifest$bounds$chunk == 1, ]
    rows <- lapply(b$start:b$end, function(gi) {
        data.frame(scenario_id = "s1", replicate = gi, analysis = "x",
            error = NA_character_, runtime_sec = 0.01, global_index = gi,
            stringsAsFactors = FALSE)
    })
    out <- list(chunk = 1L, grid_hash = manifest$grid_hash,
        simttepower_version = manifest$simttepower_version,
        simtte_version = manifest$simtte_version,
        r_version = manifest$r_version, results = do.call(rbind, rows))
    saveRDS(out, file.path(dir, simttepower:::.chunk_filename(1, 2)))

    expect_error(power_sim_merge(dir), "missing chunk")
    res <- power_sim_merge(dir, partial = TRUE)
    expect_identical(nrow(res$results), b$end - b$start + 1L)
})

test_that("power_sim_merge() errors on a grid-fingerprint mismatch", {
    dir <- tempfile()
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    manifest <- power_sim_chunks(g, n_sims = 2, seed = 1, n_chunks = 1,
        dir = dir)
    out <- list(chunk = 1L, grid_hash = "not-the-real-hash",
        simttepower_version = manifest$simttepower_version,
        simtte_version = manifest$simtte_version,
        r_version = manifest$r_version,
        results = data.frame(scenario_id = "s1", replicate = 1L,
            analysis = "x", error = NA_character_, runtime_sec = 0.01,
            global_index = 1L, stringsAsFactors = FALSE))
    saveRDS(out, file.path(dir, simttepower:::.chunk_filename(1, 1)))
    expect_error(power_sim_merge(dir), "does not match this manifest's grid")
})

test_that("power_sim_chunk()/power_sim_merge() error clearly on a bad directory/index", {
    expect_error(power_sim_chunk(tempfile(), 1), "No manifest.rds found")
    expect_error(power_sim_merge(tempfile()), "No manifest.rds found")

    dir <- tempfile()
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    power_sim_chunks(g, n_sims = 2, seed = 1, n_chunks = 2, dir = dir)
    expect_error(power_sim_chunk(dir, 0), "whole number between 1 and 2")
    expect_error(power_sim_chunk(dir, 3), "whole number between 1 and 2")
})

test_that("power_sim_chunk(cache_dir = ) sets the option during the call and restores it after", {
    skip_on_cran()
    before <- getOption("simtte.cache_dir")
    on.exit(options(simtte.cache_dir = before), add = TRUE)
    scoped_dir <- tempfile()
    dir.create(scoped_dir)

    # An analysis function that records the option while it's actually
    # in effect, to a file rather than an in-memory variable: the
    # manifest (and the analysis closures inside its grid) round-trips
    # through saveRDS()/readRDS() between power_sim_chunks() and
    # power_sim_chunk(), so the closure that actually runs is a
    # deserialized copy with its own, disconnected environment -- an
    # in-memory "seen_during <- new.env(); probe() writes to it" probe
    # would silently observe nothing (verified directly: this is exactly
    # what a first draft of this test did, and why it failed). A
    # filesystem side channel survives that round-trip; this is also, in
    # miniature, the same reason distributed execution needs plain files
    # rather than in-memory state at all (reports/07_phase3_design.md).
    seen_file <- tempfile()
    probe <- function(events) {
        writeLines(as.character(getOption("simtte.cache_dir")), seen_file)
        c(estimate = 0)
    }
    d <- .test_design(analyses = list(probe = probe))
    g <- scenario_grid(d, over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))
    dir <- tempfile()
    power_sim_chunks(g, n_sims = 1, seed = 1, n_chunks = 1, dir = dir)

    power_sim_chunk(dir, 1, progress = FALSE, cache_dir = scoped_dir)
    expect_identical(readLines(seen_file), scoped_dir)
    expect_identical(getOption("simtte.cache_dir"), before)

    # NULL (default): changes nothing, during or after. A real absolute
    # tempdir, not a bare literal string -- simtte_model_cache() creates
    # whatever simtte.cache_dir resolves to, so a relative placeholder
    # string here would actually create a directory (and a real
    # compiled-model artifact) under the working directory, which is
    # exactly what happened before this was fixed (an `R CMD check` run
    # caught it: a stray `tests/testthat/sentinel-value/` build tree).
    sentinel_dir <- tempfile()
    dir.create(sentinel_dir)
    options(simtte.cache_dir = sentinel_dir)
    power_sim_chunk(dir, 1, progress = FALSE)
    expect_identical(readLines(seen_file), sentinel_dir)
    expect_identical(getOption("simtte.cache_dir"), sentinel_dir)
})
