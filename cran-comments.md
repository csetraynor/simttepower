# CRAN submission comments (draft -- not yet submitted)

This file is prepared as part of release *prep*, not submission. See
`STATUS.md` for the release order and current state. **simttepower is
not being submitted to CRAN at the time this file was written** -- its
one hard dependency, `simtte` (>= 1.1.0), is not yet on CRAN itself.
The intended order is: simtte 1.1.0 to CRAN, then simttepower, then the
accompanying manuscript(s). This file will be revisited (and this
paragraph removed) once that order is ready to start.

## What the package does

simttepower is a companion to `simtte`: given a trial design and a grid
of scenarios that vary one or more factors, it replicates each
scenario, applies one or more analysis functions, and summarises
operating characteristics (power, type I error) across the grid,
sequentially, across local worker processes, or split into independent
chunks for a job scheduler.

## The `simtte` dependency

`Imports: simtte (>= 1.1.0)`. Every simulated trial arm is built on
`simtte::sim_tte_ode()`; the parallel/chunked execution paths build on
`simtte::simtte_prepare_model()`/`simtte_model_cache()`/
`simtte_model_cache_clear()` (all added in simtte 1.1.0, in direct
response to feedback from this package's own development --
`../simtte/reports/30_simttepower_feedback_worker_loading.md`).
simttepower cannot be submitted before `simtte` is itself on CRAN.

The dev-only `Remotes: csetraynor/simtte` entry in `DESCRIPTION`
(installs `simtte` from GitHub, since it isn't on CRAN yet) is removed
at the point `simtte` is available there -- **not removed yet**, since
removing it now would make `Imports: simtte (>= 1.1.0)` unresolvable
for anyone installing from source without also having `simtte`
pre-installed by some other route.

## R CMD check results

`R CMD check --as-cran` (both the fast, `SIMTTEPOWER_SLOW_TESTS` unset,
and the full, slow-tests-on run -- see `dev/run-tests.R --check` and
`dev/run-tests.R --check --fast`): **0 errors, 0 warnings, 1 NOTE**:

```
Maintainer: 'Carlos Traynor <carlos.traynor.qcp@gmail.com>'

New submission

Unknown, possibly misspelled, fields in DESCRIPTION:
  'Remotes'
```

Both parts of this NOTE are expected for a first submission and are not
attempted to be silenced here: "New submission" is inherent to any
package's first CRAN submission; the `Remotes` field is flagged because
it is a development-only field (see above) that will not be present in
the actual CRAN submission, once `simtte` is on CRAN and the field is
removed.

`devtools::spell_check()` (with `inst/WORDLIST` covering package-
specific/technical terms: CMRG, L'Ecuyer, PSOCK, SGE, Slurm, simtte,
tte, and a handful of British-spelling/contraction false positives):
0 errors. `urlchecker::url_check()`: all URLs valid. Per-example timings
all under 2.2s; the vignette builds in ~6s across three separate runs,
no flakiness.

## Downstream dependencies

None -- this is a new package.
