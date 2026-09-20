# simttepower: project status

One page, no phase-report reading required. For the detailed
development history, see `reports/` (not shipped with the package -- a
local, gitignored directory of design/implementation reports, one or
more per development phase).

## What the package does

**simttepower** replicates a [simtte](https://github.com/csetraynor/simtte)
(>= 1.1.0) trial design many times and summarises the operating
characteristics of an analysis applied to each replicate:

1. **Design and grid objects** (`arm()`, `trial_design()`,
   `scenario_grid()`): one or more trial arms (any `sim_tte_ode()`
   argument set, plus a label), collected with their analysis
   function(s), crossed against one or more varied factors -- a model
   parameter, a formula coefficient, a dosing regimen, a sampling
   schedule, sample size, follow-up, or covariate distribution.
2. **Analysis functions and rejection rules** (`analysis_coxph()`,
   `analysis_logrank()`, `reject_default()`, `reject_direction()`):
   simulation-side parameters are always *truth*; an analysis function
   estimates a contrast/coefficient from simulated events, never a
   nonlinear PK/PD parameter. Any `function(events, ...) -> named
   numeric` works as a custom analysis function.
3. **Execution** (`power_sim()`, `power_sim_chunks()`/
   `power_sim_chunk()`/`power_sim_merge()`): sequential, local-parallel
   (`workers = `), or split into independent chunks for a job
   scheduler (SGE/Slurm templates in `inst/templates/`) -- all three
   give byte-identical results for the same seed, verified directly
   (not assumed) in every development phase.
4. **Summarising and plotting** (`summary.simttepower_result()`,
   `plot_power()`): one row per scenario x analysis operating-
   characteristic summary, and a power/operating-characteristic curve
   from it (`ggplot2`, `Suggests`).

## Public API

| Function | What it's for |
|---|---|
| `arm()` | Define one trial arm |
| `trial_design()` | Collect arms + analysis function(s) |
| `scenario_grid()` | Cross a design against one or more varied factors |
| `analysis_coxph()` | Built-in Cox PH analysis function |
| `analysis_logrank()` | Built-in log-rank analysis function |
| `reject_default()` | `p < alpha` rejection rule |
| `reject_direction()` | Direction-aware rejection rule |
| `power_sim()` | The replication engine (sequential/local-parallel) |
| `power_sim_chunks()` | Write a chunk manifest for a grid/seed |
| `power_sim_chunk()` | Run one chunk |
| `power_sim_merge()` | Combine chunk output into one result |
| `summary.simttepower_result()` | One row per scenario x analysis OC summary |
| `plot_power()` | A power/OC curve from that summary |

One vignette: `vignette("power-analysis")`.

## Release order

simttepower depends on `simtte` (>= 1.1.0), which is **not yet on
CRAN**. The intended order is: **simtte 1.1.0 to CRAN, then
simttepower, then the accompanying manuscript(s)**. Nothing is
submitted to CRAN until that order is ready to start -- see
`cran-comments.md` for the current submission-readiness checklist
(release *prep*, not submission). The dev-only `Remotes:
csetraynor/simtte` entry in `DESCRIPTION` is removed at the point
simtte itself is on CRAN.

## Roadmap (not built)

- **Bias and coverage operating characteristics.** `scenario_grid(truth
  = )` and `reject_direction()` already read a per-scenario truth for
  direction-aware rejection; a bias/coverage summary alongside power/
  type-I-error would read the same `truth`, not add a new input. Not
  built -- no current design calling for it.
- **Ragged grids** (a different `n_sims` per scenario). The
  global-index -> RNG-stream mapping
  (`(scenario_row - 1) * n_sims + replicate`) assumes one rectangular
  `n_sims` for the whole grid (`reports/01_phase1_plan.md` section 5);
  a ragged grid needs a registration-order index instead. Not built --
  nothing yet calls for it.
- **C3 (PK/PD-state-dependent visits)**: blocked upstream, not a
  simttepower gap. simtte itself has not built a visit process that
  reacts to a subject's simulated PK/PD state (`sim_tte`'s own
  `STATUS.md` roadmap) -- simttepower can only replicate designs simtte
  can simulate, so this stays on simtte's roadmap, not duplicated here
  as separate simttepower work.
