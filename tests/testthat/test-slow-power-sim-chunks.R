# Phase 3 slow tests: real chunk/merge round trips. Gated behind
# SIMTTEPOWER_SLOW_TESTS (see dev/run-tests.R --check). Never more than 2
# workers inside a chunk (CRAN policy). All file I/O goes to tempfile().

.run_all_chunks <- function(g, n_sims, seed, n_chunks, dir) {
    power_sim_chunks(g, n_sims = n_sims, seed = seed, n_chunks = n_chunks,
        dir = dir)
    for (i in seq_len(n_chunks)) power_sim_chunk(dir, i, progress = FALSE)
    power_sim_merge(dir)
}

test_that("chunk/merge equals sequential power_sim() for k = 1, 3, and a non-divisor", {
    skip_if_not_slow()
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1, 3)))
    n_sims <- 5  # 2 scenarios x 5 = 10 tasks
    seed <- 77

    r_seq <- power_sim(g, n_sims = n_sims, seed = seed, progress = FALSE)
    cols <- setdiff(names(r_seq$results), "runtime_sec")

    # k = 1: one chunk, the whole run.
    # k = 3: 10 tasks / 3 chunks -- not a divisor, forces unequal chunk sizes.
    # k = 10: a divisor (every chunk size 1) -- the other edge.
    for (k in c(1L, 3L, 10L)) {
        dir <- tempfile()
        r_chunked <- .run_all_chunks(g, n_sims, seed, k, dir)
        expect_identical(r_seq$results[cols], r_chunked$results[cols],
            info = paste("k =", k))
    }
})

test_that("re-running one chunk produces an identical chunk_<i>.rds", {
    skip_if_not_slow()
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1, 3)))
    dir <- tempfile()
    power_sim_chunks(g, n_sims = 4, seed = 5, n_chunks = 3, dir = dir)

    out1 <- power_sim_chunk(dir, 2, progress = FALSE)
    f <- file.path(dir, simttepower:::.chunk_filename(2, 3))
    saved1 <- readRDS(f)
    out2 <- power_sim_chunk(dir, 2, progress = FALSE)
    saved2 <- readRDS(f)

    cols <- setdiff(names(saved1$results), "runtime_sec")
    expect_identical(saved1$results[cols], saved2$results[cols])
    expect_identical(out1$results[cols], out2$results[cols])
})

test_that("power_sim_merge(partial = TRUE) merges a real subset of chunks", {
    skip_if_not_slow()
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1, 3)))
    dir <- tempfile()
    power_sim_chunks(g, n_sims = 4, seed = 9, n_chunks = 3, dir = dir)
    power_sim_chunk(dir, 1, progress = FALSE)
    power_sim_chunk(dir, 3, progress = FALSE)
    # chunk 2 never run

    expect_error(power_sim_merge(dir), "missing chunk file\\(s\\) for chunk\\(s\\) 2")
    res <- power_sim_merge(dir, partial = TRUE)
    manifest <- readRDS(file.path(dir, "manifest.rds"))
    b1 <- manifest$bounds[manifest$bounds$chunk == 1, ]
    b3 <- manifest$bounds[manifest$bounds$chunk == 3, ]
    expect_identical(sort(unique(res$results$global_index)),
        sort(c(seq(b1$start, b1$end), seq(b3$start, b3$end))))
})

test_that("a chunk can use its own local workers, independent of n_chunks", {
    skip_if_not_slow()
    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1, 3)))
    n_sims <- 4
    seed <- 13
    r_seq <- power_sim(g, n_sims = n_sims, seed = seed, progress = FALSE)
    cols <- setdiff(names(r_seq$results), "runtime_sec")

    dir <- tempfile()
    power_sim_chunks(g, n_sims = n_sims, seed = seed, n_chunks = 2, dir = dir)
    power_sim_chunk(dir, 1, workers = 2, parallel = "psock", progress = FALSE)
    power_sim_chunk(dir, 2, workers = 2, parallel = "psock", progress = FALSE)
    res <- power_sim_merge(dir)
    expect_identical(r_seq$results[cols], res$results[cols])
})

test_that("clear_cache = TRUE clears simtte's model cache and the run still succeeds", {
    skip_if_not_slow()
    old_cache_dir <- getOption("simtte.cache_dir")
    fresh_dir <- tempfile()
    dir.create(fresh_dir)
    options(simtte.cache_dir = fresh_dir)
    on.exit(options(simtte.cache_dir = old_cache_dir), add = TRUE)

    g <- scenario_grid(.test_design(), over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))

    res <- power_sim(g, n_sims = 2, seed = 1, progress = FALSE,
        clear_cache = TRUE)
    expect_true(all(is.na(res$results$error)))
    expect_identical(list.files(simtte::simtte_model_cache()), character(0))

    # clear_cache = FALSE (default): the cache stays populated.
    res2 <- power_sim(g, n_sims = 2, seed = 1, progress = FALSE)
    expect_true(all(is.na(res2$results$error)))
    expect_true(length(list.files(simtte::simtte_model_cache())) > 0)
})

test_that("clear_cache = TRUE still clears the cache when the run errors mid-way", {
    skip_if_not_slow()
    old_cache_dir <- getOption("simtte.cache_dir")
    fresh_dir <- tempfile()
    dir.create(fresh_dir)
    options(simtte.cache_dir = fresh_dir)
    on.exit(options(simtte.cache_dir = old_cache_dir), add = TRUE)

    d <- .test_design()
    d$end <- NULL
    d$arms <- lapply(d$arms, function(a) { a$end <- NULL; a })
    g <- scenario_grid(d, over = list(arm = "experimental",
        field = "param.IC50", values = c(1)))

    res <- power_sim(g, n_sims = 1, seed = 1, progress = FALSE,
        clear_cache = TRUE)
    expect_true(all(!is.na(res$results$error)))  # every replicate errored
    expect_identical(list.files(simtte::simtte_model_cache()), character(0))
})
