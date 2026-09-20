# simttepower 0.1.0

First release. A companion to [simtte](https://github.com/csetraynor/simtte)
(>= 1.1.0): trial replication and simulation-based power/operating-
characteristic analysis on top of simtte's single-cohort PK/PD
time-to-event simulator.

## Design and grid objects

* `arm()`, `trial_design()`: define one or more trial arms (any
  `sim_tte_ode()` argument set, plus a label) and collect them with
  their analysis function(s).
* `scenario_grid()`: cross a base design against one or more varied
  factors -- a model parameter, a formula coefficient, a dosing
  regimen, a sampling schedule, sample size, follow-up, or covariate
  distribution -- via `expand.grid()`-style crossing, with an optional
  per-scenario `truth` for direction-aware rejection.

## Analysis functions and rejection rules

* `analysis_coxph()`, `analysis_logrank()`: built-in analysis
  functions covering the estimand boundary (simulation-side parameters
  are truth; an analysis function estimates a contrast/coefficient from
  simulated events and their `arm`/`regimen`/`dose`/`covariates`
  labels). Any `function(events, ...) -> named numeric` also works.
* `reject_default()` (`p < alpha`, auto-detecting the p-value column),
  `reject_direction()` (additionally requires the estimate's sign to
  match a scenario's declared `truth`).

## Execution

* `power_sim()`: the replication engine. Sequential by default;
  `workers = ` dispatches across local worker processes (PSOCK,
  cross-platform, or fork, Unix-only) with byte-identical results to
  the sequential run for the same seed. `clear_cache = ` optionally
  clears simtte's compiled-model cache after a run.
* `power_sim_chunks()`/`power_sim_chunk()`/`power_sim_merge()`: split a
  run into independent chunks that can execute as separate processes --
  on a job scheduler (SGE/Slurm array-job templates ship in
  `inst/templates/`) or just in a loop on one machine -- and merge them
  into the same result a single `power_sim()` call would have produced.
  No scheduler dependency: plain files are the entire mechanism.

## Summarising and plotting

* `summary.simttepower_result()`: one row per scenario x analysis
  operating-characteristic summary (rejection rate and its binomial SE,
  error counts, median event/runtime summaries).
* `plot_power()`: a power/operating-characteristic curve over one
  varied factor from that summary, with an optional second factor
  (colour), a facet, and a binomial CI ribbon. Needs `ggplot2`
  (`Suggests`).
