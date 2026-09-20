# Postcard power reproduction

A worked, HPC-shaped reproduction of the `simtte_postcard` project's own
PK/PD dose-response power analysis (`../simtte_postcard/scripts/
pkpd_power_*.R`, `../simtte_postcard/sge/`), rebuilt on the current
simtte + simttepower API. This is the real-world stress test the
chunk/merge layer was built for -- see `reports/10_phase4_followup_report.md`
in the simttepower source tree for the full account, including every
piece of API friction this exercise found.

**These scripts are examples, not tests.** They are not run by
`R CMD check` or the test suite; copy and adapt them.

## What the postcard did

Three dose-contrast scenarios (`low_vs_std`: amt 10 vs 100;
`std_vs_boost`: 100 vs 200; `std_vs_high`: 100 vs 400), a hand-written
mrgsolve PK/PD model (one-compartment PK, an indirect-response mediator
the drug inhibits, hazard = `H0 * (R / R0)`), 500 replicates per
scenario at a fixed 400-subjects-per-arm cohort, then *nested subsetting*
of each cohort down to 5 sample sizes (25, 50, 100, 200, 400) for a
`coxph(Surv(sim_time, sim_status) ~ arm)` fit at each size -- 1,500 full
simulations producing 7,500 result rows. Between-subject variability
came from a precomputed 1,500,000-row ETA pool (fixed seed), sliced by
hand-computed offsets so every (scenario, replicate, arm) got a unique,
non-overlapping draw. Orchestrated via an SGE array job
(`../simtte_postcard/sge/run_job.sh`) with `seed = 10000 + task_id`.

## How it maps onto the current API

| Postcard | Here |
|---|---|
| `pkpd_power_00_setup.R` (model, ETA pool, grid) | `00_plan.R` |
| `pkpd_power_02_simulate.R` (one SGE array task) | `01_worker.R` |
| `pkpd_power_03_aggregate.R` (pool + power curve) | `02_merge_report.R` |
| `sge/run_job.sh` + `submit.sh` | `sge_array.sh` / `slurm_array.sh` |
| Hand-written mrgsolve model | `simtte::tte_model()` conversion of the *same* PK/PD code (see `00_plan.R`'s own comment on why not `irm1_hazard`) |
| 1.5M-row ETA pool + offset arithmetic | A native mrgsolve `$OMEGA`/`ETA(<label>)` block on the converted model -- no pool, no R-level bookkeeping |
| `seed = 10000 + task_id` | The manifest's own L'Ecuyer streams (`power_sim_chunks()`); the array task id only selects which rows a chunk owns |
| Nested subsetting across sample sizes | Each sample size is its own scenario, fully simulated (see `02_author_decisions.md`, "After the Phase 1 plan" decision 1 -- a deliberate simttepower design choice, more compute for a simpler, more general model) |
| `power = mean(pvalue < alpha & estimate < 0)` | `reject_direction()`, with each scenario's `truth` set to a negative placeholder (dose is expected protective in all 3 contrasts) |

## Running the smoke config locally

```r
Sys.setenv(POSTCARD_WORK_DIR = tempfile())
```

```sh
Rscript 00_plan.R                       # writes the manifest (fast)
Rscript 01_worker.R 1                   # chunk 1
Rscript 01_worker.R 2                   # chunk 2 (smoke uses 2 chunks)
Rscript 02_merge_report.R               # summary table + power_curves.png
```

`POSTCARD_SMOKE` defaults to the smoke config (2 small sample sizes, 4
replicates -- seconds, not a real power estimate, just a sanity check
that the whole pipeline runs and produces sensible output). Set
`POSTCARD_SMOKE=false` for the full, postcard-scale config (7,500 tasks,
50 chunks) -- **do not run the full config's chunks locally**; it is
HPC-scale by design (see "Runtime scale" below). `00_plan.R`/
`02_merge_report.R` are always fast regardless (no simulation).

## Running the full config on a scheduler

```sh
export POSTCARD_WORK_DIR=/path/to/a/real/directory   # NOT tempdir() -- must
                                                       # persist across jobs
POSTCARD_SMOKE=false Rscript 00_plan.R
# SGE:
qsub sge_array.sh
# Slurm:
sbatch slurm_array.sh
# once every task is done:
Rscript 02_merge_report.R
```

## The model-cache gotcha (read this before running on a scheduler)

`00_plan.R` and `01_worker.R` both set `options(mrgsolve.soloc = ,
mrgsolve.project = )` to `$POSTCARD_WORK_DIR/model_cache` -- **required**,
not an optimisation: `tte_model()`'s own compiled artifact lives
wherever those options point at *build* time, which defaults to a
process's own `tempdir()` -- gone the moment `00_plan.R`'s process exits.
A genuinely separate worker process (the real array-job case) would
otherwise fail with `"[loadso] the model dll file doesn't exist"` --
found directly by running this reproduction as real, separate `Rscript`
processes, not assumed. Keep `POSTCARD_WORK_DIR` pointed at a real,
persistent, shared-filesystem directory for a real array job -- never
`tempdir()`. See `reports/10_phase4_followup_report.md` "API friction
and findings" item 3 for the full account and the fix recommended for a
future simttepower/simtte session.

## Runtime scale

Smoke config: seconds, end to end. Full config: HPC-scale by design --
7,500 full two-arm simulations (up to 800 subjects, 24 months follow-up,
matching the postcard's own real workload), split across 50 chunks (150
tasks per chunk). Not benchmarked in full here (that needs the HPC this
reproduction targets); size chunks/workers-per-chunk to your own
cluster's node count and per-task memory the way you would for any
array job.
