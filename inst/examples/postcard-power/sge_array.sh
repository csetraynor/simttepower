#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -V
#$ -N postcard_power_chunk
#$ -t 1-50
#$ -o logs/$JOB_NAME.$JOB_ID.$TASK_ID.out
#$ -e logs/$JOB_NAME.$JOB_ID.$TASK_ID.err

# SGE array script for the postcard-power reproduction (full, postcard-
# scale config: 50 chunks -- must match 00_plan.R's own n_chunks; update
# both together if you change one). Adapted from
# inst/templates/sge_array.sh; see that file's own README for the
# general pattern this follows.
#
# Before submitting:
#   1. Rscript 00_plan.R (POSTCARD_SMOKE unset/"true" for a quick check,
#      "false" for the real, postcard-scale run) -- writes
#      $POSTCARD_WORK_DIR/manifest.rds.
#   2. Set POSTCARD_WORK_DIR below to the same directory (export it, or
#      edit the line under "Config" -- qsub -v does not inherit your
#      shell's own exported variables unless you re-list them here).
#   3. qsub sge_array.sh
#   4. Once every task has finished: Rscript 02_merge_report.R (same
#      POSTCARD_WORK_DIR).

set -euo pipefail
mkdir -p logs

# ---- Config -----------------------------------------------------------
export POSTCARD_WORK_DIR="${POSTCARD_WORK_DIR:?Set POSTCARD_WORK_DIR to the directory 00_plan.R wrote its manifest into}"
# -------------------------------------------------------------------------

echo "[$(date)] Host: $(hostname)  JOB_ID=$JOB_ID  SGE_TASK_ID=$SGE_TASK_ID"

# SGE_TASK_ID only ever selects *which rows of the manifest's own
# precomputed task table* this array task owns -- it is never used to
# derive a seed (see inst/templates/templates_README.md). The seed lives
# once, on the manifest 00_plan.R wrote.
Rscript "$(dirname "$0")/01_worker.R" "${SGE_TASK_ID}"

echo "[$(date)] Done."
