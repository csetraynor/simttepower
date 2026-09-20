#!/bin/bash
#SBATCH --job-name=postcard_power_chunk
#SBATCH --array=1-50
#SBATCH --output=logs/%x.%A.%a.out
#SBATCH --error=logs/%x.%A.%a.err

# Slurm array script for the postcard-power reproduction (full,
# postcard-scale config: 50 chunks -- must match 00_plan.R's own
# n_chunks; update both together if you change one). Adapted from
# inst/templates/slurm_array.sh; see that file's own README for the
# general pattern this follows.
#
# Before submitting:
#   1. Rscript 00_plan.R (POSTCARD_SMOKE unset/"true" for a quick check,
#      "false" for the real, postcard-scale run) -- writes
#      $POSTCARD_WORK_DIR/manifest.rds.
#   2. Set POSTCARD_WORK_DIR below to the same directory.
#   3. sbatch slurm_array.sh
#   4. Once every task has finished: Rscript 02_merge_report.R (same
#      POSTCARD_WORK_DIR).

set -euo pipefail
mkdir -p logs

# ---- Config -----------------------------------------------------------
export POSTCARD_WORK_DIR="${POSTCARD_WORK_DIR:?Set POSTCARD_WORK_DIR to the directory 00_plan.R wrote its manifest into}"
# -------------------------------------------------------------------------

echo "[$(date)] Host: $(hostname)  JOB_ID=$SLURM_JOB_ID  ARRAY_TASK_ID=$SLURM_ARRAY_TASK_ID"

# SLURM_ARRAY_TASK_ID only ever selects *which rows of the manifest's own
# precomputed task table* this array task owns -- it is never used to
# derive a seed (see inst/templates/templates_README.md). The seed lives
# once, on the manifest 00_plan.R wrote.
Rscript "$(dirname "$0")/01_worker.R" "${SLURM_ARRAY_TASK_ID}"

echo "[$(date)] Done."
