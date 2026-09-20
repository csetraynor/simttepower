#!/usr/bin/env Rscript
# =============================================================================
# 01_worker.R -- run one chunk of the postcard-power manifest.
# =============================================================================
# What one array-job task calls. Reads its own chunk index from the first
# command-line argument (the array task id, via sge_array.sh/slurm_array.sh
# -- see this example's README.md), runs that chunk's own share of the task
# list, writes chunk_<i>.rds into the work directory. Never derives a seed
# from the task id -- the seed lives once, on the manifest 00_plan.R wrote
# (see inst/templates/templates_README.md for why this matters).
#
# Inputs:  <work_dir>/manifest.rds (from 00_plan.R)
# Outputs: <work_dir>/chunk_<i>.rds
#
# Usage:
#   Rscript 01_worker.R <chunk index>
#   (called by sge_array.sh/slurm_array.sh with the array task id; or in a
#   loop for a local check -- see README.md "Running the smoke config
#   locally")
#
# Runtime: SMOKE config, well under a second per chunk. FULL config, per
# the postcard's own real timings, expect single-digit seconds per
# replicate (a full 800-subject two-arm cohort at end = 24 months) times
# however many tasks this chunk owns -- see README.md "Runtime scale".
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
i <- suppressWarnings(as.integer(args[1]))
if (is.na(i) || i < 1) {
  stop("Usage: Rscript 01_worker.R <chunk index> (a whole number, 1-based)")
}

work_dir <- Sys.getenv("POSTCARD_WORK_DIR",
  file.path(tempdir(), "postcard-power-work"))

# MUST match 00_plan.R's own mrgsolve.soloc/project setting exactly -- see
# 00_plan.R's own comment ("A real gap found by this reproduction") for
# why: the grid's tte_model()-converted model was compiled once, in
# 00_plan.R's own process, into this directory; this worker process only
# ever loadso()s the already-compiled artifact there, never rebuilds.
model_cache_dir <- file.path(work_dir, "model_cache")
options(mrgsolve.soloc = model_cache_dir, mrgsolve.project = model_cache_dir)

suppressPackageStartupMessages(library(simttepower))

power_sim_chunk(work_dir, i, progress = FALSE)

cat(sprintf("[worker] Chunk %d done, written into %s\n", i, work_dir))
