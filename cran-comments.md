# CRAN submission comments (draft -- not yet submitted)

This file is prepared as part of release *prep*. See `STATUS.md` for the
release order and current state. The intended order was: simtte to CRAN,
then simttepower, then the accompanying manuscript(s). `simtte` 2.0.0
reached CRAN on 2026-11-07, so the dependency that previously blocked
this submission is now a published CRAN package and simttepower's
`Imports` is satisfiable from CRAN alone.

## What the package does

simttepower is a companion to `simtte`: given a trial design and a grid
of scenarios that vary one or more factors, it replicates each
scenario, applies one or more analysis functions, and summarises
operating characteristics (power, type I error) across the grid,
sequentially, across local worker processes, or split into independent
chunks for a job scheduler.

## The `simtte` dependency

`Imports: simtte (>= 2.0.0)`, a published CRAN package. Every simulated
trial arm is built on `simtte::sim_tte_ode()`; the parallel and chunked
execution paths build on `simtte::simtte_prepare_model()`,
`simtte_model_cache()` and `simtte_model_cache_clear()`. All four are
exported by `simtte` 2.0.0. simttepower calls no `simtte` internals.

The version bound is `>= 2.0.0` because `sim_tte_ode()` and the
model-preparation functions above are not present in the previous CRAN
release (1.0.2).

## R CMD check results

`R CMD check --as-cran` with the slow tests on (`dev/run-tests.R
--check`): **0 errors, 0 warnings, 1 NOTE**:

```
Maintainer: 'Carlos Traynor <carlos.traynor.qcp@gmail.com>'

New submission
```

"New submission" is inherent to any package's first CRAN submission and
is not attempted to be silenced here. It is the only NOTE.

Checked 2026-11-07 against `simtte` 2.0.0 installed from CRAN
(`packageDescription("simtte")$Repository` is `CRAN`). The test suite
passes with `SIMTTEPOWER_SLOW_TESTS` unset and set; with it set, 224
passing, 0 failures, and 2 skips (a Windows-only fork-cluster test, and
one test guarded on `ggplot2` being absent).

`devtools::spell_check()` (with `inst/WORDLIST` covering package-
specific/technical terms: CMRG, L'Ecuyer, PSOCK, SGE, Slurm, simtte,
tte, and a handful of British-spelling/contraction false positives):
0 errors. `urlchecker::url_check()`: all URLs valid. Per-example timings
all under 2.2s; the vignette builds in ~6s across three separate runs,
no flakiness.

## Downstream dependencies

None -- this is a new package.
