# Chunk/merge templates

Two array-job scripts (`sge_array.sh`, `slurm_array.sh`) for running a
`power_sim()` as a job-scheduler array instead of one long-running
process, plus this README. Neither script is run by simttepower's own
tests (they need a real scheduler) -- they are documentation, reviewed
by hand for correctness.

No scheduler dependency in the package: `power_sim_chunks()`,
`power_sim_chunk()`, and `power_sim_merge()` use plain files
(`manifest.rds` plus one `chunk_<i>.rds` per chunk) as their entire
mechanism. These scripts are thin wrappers around `power_sim_chunk()`;
the same flow works with no scheduler at all, just calling
`power_sim_chunk(dir, i)` in a loop or in parallel jobs of your own.

**These two scripts are examples to copy and adapt for your own
scheduler/queue/account settings -- they are not executed by simttepower
or its tests, and no CRAN check machine has a scheduler to run them
against.** The tested contract is the three R functions they call
(`power_sim_chunks()`/`power_sim_chunk()`/`power_sim_merge()`), covered
directly by simttepower's own test suite (byte-identity against a
sequential `power_sim()` run, missing/mismatched-chunk errors, and so
on); the shell layer around them is reviewed by hand, not by a test.
Misuse of the R functions themselves -- calling `power_sim_chunk()`
before `power_sim_chunks()` has written a manifest, or with an `i`
outside `1:n_chunks` -- gives a clear, tested error either way.

## The flow

```r
# 1. From R, once: write the manifest. Runs no simulation.
power_sim_chunks(grid, n_sims = 500, seed = 1, n_chunks = 20,
  dir = "work")

# 2. Submit the array (SGE: qsub sge_array.sh; Slurm: sbatch
#    slurm_array.sh), after setting N_CHUNKS in the script to the same
#    20 used above. Each array task calls:
#    power_sim_chunk("work", <task id>, progress = FALSE)

# 3. From R, once every task has finished: combine.
res <- power_sim_merge("work")
summary(res)
```

`power_sim_merge()` errors and names any chunk that never finished
(a failed or still-running array task) unless you pass
`partial = TRUE` to merge what is present, accepting the gap.

## Why the seed never touches the array task id

A prior project (`simtte_postcard`'s own SGE workflow) computed each
task's seed as `10000 + task_id`. That ties reproducibility to how many
tasks you happened to submit and in what order they were numbered --
resubmitting with a different array size, or re-running one failed task
under a different task id, silently changes which random draws that
task used.

`power_sim_chunks()`/`power_sim_chunk()` don't do this. The seed is set
**once**, when you call `power_sim_chunks()`, and stored on the
manifest. Every chunk (`power_sim_chunk(dir, i)`) reads that same seed
back from the manifest and derives the *entire* run's stream sequence
from it -- `i` only ever selects which rows of that sequence this chunk
owns, never how the sequence itself is generated. Replicate `k` of
scenario `s` therefore always draws from the same L'Ecuyer-CMRG stream,
regardless of `n_chunks`, which task ran which chunk, or what order
tasks finished in -- the same invariant `power_sim(workers = )` already
gives you for local parallelism, now extended across processes/machines.

## Model cache across array tasks

Each array task is a fresh R process with no memory of what a sibling
task already built -- `power_sim_chunk()` prepares its own models
independently every time, the same way it would for `workers = 1`/
`workers > 1` locally (see `?power_sim_chunk`). This needs no shared
filesystem to be *correct*.

If your cluster's nodes *do* share a filesystem (common for SGE/Slurm),
you can optionally speed this up by pointing every task at the same
persistent model cache directory, so task 2 onward hits task 1's
already-built artifact instead of rebuilding:

```r
options(simtte.cache_dir = "/shared/path/simtte-cache")
```

Set this (e.g. in an `.Rprofile` the array tasks share, or before the
`power_sim_chunk()` call in the script above) if you want it --
`simtte::simtte_model_cache()` already keys that directory by R/simtte/
mrgsolve version, so it's safe to point at a long-lived shared location.
Not required, and not something `power_sim_chunk()` sets for you.
