# CRAN submission comments (draft -- not yet submitted)

**This package is not being submitted to CRAN at the time this file was
written.** Its one hard dependency, `simtte` (>= 1.1.0), is not yet on
CRAN. The intended release order is: **simtte 1.1.0 to CRAN, then
simttepower, then the accompanying manuscript(s)** (see `STATUS.md`).
The rest of this file is written as it would read for the eventual real
submission, once that order is ready to start -- kept up to date as
release prep continues, not a placeholder to fill in later from
scratch.

## Summary

simttepower is a companion to `simtte`, providing trial replication and
simulation-based power/operating-characteristic analysis on top of
simtte's single-cohort PK/PD time-to-event simulator. A run can execute
sequentially, across local worker processes, or split into independent
chunks for a job scheduler, giving byte-identical results for the same
seed in every mode.

## Test environments

Run this session:

* local: macOS (Darwin 25.6.0, arm64), R 4.6.0, `R CMD check --as-cran`
  (`devtools::check()`/`dev/run-tests.R --check`), both with and
  without the slow test suite (`SIMTTEPOWER_SLOW_TESTS`).

Intended before actual submission (not yet run in this session -- no
CI/r-hub access from this environment):

* `rhub::rhub_check()` (or `rhub::check_for_cran()`, whichever the
  installed `rhub` version at submission time provides), covering at
  least a Linux (R-devel and R-release), a Windows, and a macOS target.
* `usethis::use_github_action("check-standard")`-style GitHub Actions
  matrix (ubuntu-latest, windows-latest, macos-latest, each
  R-release; ubuntu-latest R-devel) -- once this package has a public
  GitHub remote reachable by Actions, since it's presently developed
  privately.
* `devtools::check_win_devel()` (win-builder), the traditional
  Windows-specific check CRAN itself has historically weighted.

None of these run automatically yet; each depends on `simtte` already
being resolvable (installable) on the target platform, which in turn
depends on `simtte`'s own CRAN status -- see the release-order note
above.

## R CMD check results

`R CMD check --as-cran`, both `SIMTTEPOWER_SLOW_TESTS` unset (fast) and
set (full, real PSOCK/fork/chunk execution) -- see
`dev/run-tests.R --check --fast` / `--check`:

```
0 errors | 0 warnings | 1 note
```

```
❯ checking CRAN incoming feasibility ... NOTE
  Maintainer: 'Carlos Traynor <carlos.traynor.qcp@gmail.com>'

  New submission

  Unknown, possibly misspelled, fields in DESCRIPTION:
    'Remotes'
```

Both parts of this NOTE are expected and not attempted to be silenced:

* **"New submission"** is inherent to any package's first CRAN
  submission -- nothing to fix.
* **The `Remotes` field** is a development-only entry
  (`Remotes: csetraynor/simtte`, installing `simtte` from GitHub since
  it isn't on CRAN yet). It is **removed** at the point `simtte` itself
  reaches CRAN -- not removed yet, since doing so now would make
  `Imports: simtte (>= 1.1.0)` unresolvable for a source install
  without `simtte` already present by some other route. The actual
  CRAN submission will not carry this field; this NOTE will not recur.

No other NOTEs, WARNINGs, or ERRORs at any check level used this
session. `devtools::spell_check()` (`inst/WORDLIST` covering
package-specific/technical terms): 0 errors. `urlchecker::url_check()`:
all URLs valid. Per-example timings all under 2.2s (captured from a
real `R CMD check --timings` run, not estimated); the one vignette
builds in ~6s across three separate, non-flaky runs.

## Downstream dependencies

None -- this is a new package, first submission.

## Dependency note for the CRAN reviewer

`Imports: simtte (>= 1.1.0)`. Every simulated trial arm in simttepower
is built on `simtte::sim_tte_ode()`; simttepower's parallel and
chunked-execution paths build on `simtte::simtte_prepare_model()`/
`simtte_model_cache()`/`simtte_model_cache_clear()` (all present in
`simtte` 1.1.0). **This submission will not be made until `simtte` is
itself available on CRAN** -- attempting to submit simttepower first
would fail `R CMD check`'s own dependency resolution for any reviewer
or user without `simtte` already installed from another source.

## Policy notes

* No compiled code of simttepower's own (no `src/`); `simtte`'s own
  compiled dependency (`mrgsolve`, via `simtte`) is unaffected by this
  package.
* No internet access, no writes outside a session temp directory by
  default in any example/test/vignette; `power_sim(clear_cache = )`/
  `power_sim_chunk(clear_cache = , cache_dir = )` only ever touch a
  location the caller explicitly names or `simtte`'s own default
  session-temp cache.
* No more than 2 cores/workers used in any example or test (parallel
  examples are additionally guarded on `parallel::detectCores() >= 2`
  and CRAN via `skip_on_cran()` where they spawn real worker
  processes).
