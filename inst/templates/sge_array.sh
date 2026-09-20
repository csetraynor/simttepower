#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -V
#$ -N simttepower_chunk
#$ -t 1-N_CHUNKS
#$ -o logs/$JOB_NAME.$JOB_ID.$TASK_ID.out
#$ -e logs/$JOB_NAME.$JOB_ID.$TASK_ID.err

# SGE array template for a power_sim_chunks()/power_sim_chunk()/
# power_sim_merge() run. See templates_README.md in this same directory
# for the full flow and why the seed lives on the manifest, never here.
#
# Before submitting:
#   1. Run power_sim_chunks(grid, n_sims, seed, n_chunks = N, dir = "work")
#      once, from R, to write work/manifest.rds.
#   2. Replace N_CHUNKS below with that same N (must match `#$ -t 1-N`).
#   3. `qsub sge_array.sh`
#   4. Once every task has finished, run power_sim_merge("work") from R.

set -euo pipefail
mkdir -p logs

echo "[$(date)] Host: $(hostname)  JOB_ID=$JOB_ID  SGE_TASK_ID=$SGE_TASK_ID"

# SGE_TASK_ID only ever selects *which rows of the manifest's own
# precomputed task table* this array task owns (power_sim_chunk()'s `i`
# argument) -- it is never used to derive a seed. The seed lives once,
# on the manifest written by power_sim_chunks(), untouched by every
# chunk/task afterward. Do not add a per-task seed offset here (e.g.
# "seed = 10000 + task_id") -- that breaks the one invariant this whole
# mechanism exists to provide: replicate k of scenario s always draws
# from the same stream, regardless of how the run was chunked.
Rscript -e "simttepower::power_sim_chunk('work', ${SGE_TASK_ID}, progress = FALSE)"

echo "[$(date)] Done."
