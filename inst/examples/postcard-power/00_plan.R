#!/usr/bin/env Rscript
# =============================================================================
# 00_plan.R -- build the design/grid and write the chunk manifest.
# =============================================================================
# Reproduces, on the current simtte/simttepower API, the PK/PD dose-response
# power analysis from ../simtte_postcard/scripts/pkpd_power_*.R (see this
# example's own README.md for the full mapping and what changed). Runs no
# simulation -- power_sim_chunks() only partitions the task list and writes
# a manifest.
#
# Usage:
#   Rscript 00_plan.R           # smoke config (fast, for a local check)
#   POSTCARD_SMOKE=false Rscript 00_plan.R   # full, postcard-scale config
#
# Output: <work_dir>/manifest.rds (+ manifest.txt), printed at the end.
# Runtime: seconds, either config (writes no simulation output).
# =============================================================================

suppressPackageStartupMessages(library(simttepower))

smoke <- !identical(Sys.getenv("POSTCARD_SMOKE"), "false")

work_dir <- Sys.getenv("POSTCARD_WORK_DIR",
  file.path(tempdir(), "postcard-power-work"))
dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)

# A real gap found by this reproduction, not assumed: a tte_model()-
# converted model's compiled artifact lives wherever mrgsolve's own
# soloc/project options pointed at *build* time (tte_model()'s own
# mcode_cache() call, independent of simtte.cache_dir -- that option is
# only consulted by simtte_prepare_model()/sim_tte_ode()'s built-in-model
# path). Those options default to tempdir(), which is deleted the moment
# 00_plan.R's own R process exits -- so a worker process reading the
# manifest later (01_worker.R, genuinely separate, exactly the real
# array-job case) fails with "[loadso] the model dll file doesn't exist",
# confirmed directly, not assumed: power_sim_chunk() only re-prepares
# models via simtte::simtte_prepare_model() when workers > 1, and even
# then, simtte_prepare_model() on an already-tte_model()-converted object
# only ever loadso()s its existing (now-stale) artifact -- it does not
# rebuild from source. See README.md "API friction and findings" item 3
# for the full writeup and the recommendation this produced. Worked
# around here, at the *example* level (never inside simttepower's own
# package code, which must never set a global mrgsolve option): point
# mrgsolve's own soloc/project at a directory that outlives any one
# process, shared by every script in this example via the same
# POSTCARD_WORK_DIR.
model_cache_dir <- file.path(work_dir, "model_cache")
dir.create(model_cache_dir, recursive = TRUE, showWarnings = FALSE)
options(mrgsolve.soloc = model_cache_dir, mrgsolve.project = model_cache_dir)

# ---------------------------------------------------------------------------
# The model
# ---------------------------------------------------------------------------
# The postcard's own hand-written mrgsolve model (pkpd_power_00_setup.R),
# unchanged in its PK/PD structure and hazard form -- one-compartment PK
# with first-order subcutaneous absorption, coupled to an indirect-response
# mediator R that the drug inhibits production of; hazard is the *ratio*
# H0 * (R / R0), not simtte's built-in irm1_hazard's exponential-relative-
# deviation link (H0 * exp(lp + beta_r * (R/R0 - 1))) -- structurally
# similar (same indirect-response ODE), but not the same hazard formula, so
# using irm1_hazard directly would silently change the model being
# reproduced. tte_model() converts the postcard's own code instead, which
# is the faithful choice here (see README.md "Model choice").
#
# Between-subject variability: the postcard drew a 1,500,000-row ETA pool
# once (fixed seed) and sliced/offset it by hand into every task's data
# columns, specifically to work around ETAs not being injectable any other
# way at the time. That whole apparatus is unnecessary here: this model
# declares its own $OMEGA block using mrgsolve's native ETA(<label>) idiom
# (not the postcard's own manual "exp(ECL)"-as-a-data-column pattern, which
# only worked because every task called zero_re() to disable mrgsolve's own
# draw) -- simtte's omega= idata route is reserved for the six built-in
# hazard-library models (?sim_tte_ode "Between-subject variability"), but a
# tte_model()-converted model with its own declared $OMEGA block gets BSV
# from mrgsolve's own per-subject draw automatically, no pool, no offsets,
# no R-level bookkeeping at all. See README.md "API friction and findings"
# item 1.
pkpd_code <- '
$PARAM CL=2, V=20, KA=1, KIN=1, KOUT=0.5, IC50=1, IMAX=0.9

$CMT GUT CENT R

$OMEGA @labels ECL EV EIC50
0.09 0.09 0.16

$MAIN
double CLi   = CL * exp(ETA(ECL));
double Vi    = V  * exp(ETA(EV));
double IC50i = IC50 * exp(ETA(EIC50));
R_0 = KIN / KOUT;

$ODE
double CP  = CENT / Vi;
double INH = IMAX * CP / (IC50i + CP);
dxdt_GUT  = -KA * GUT;
dxdt_CENT =  KA * GUT - (CLi / Vi) * CENT;
dxdt_R    =  KIN * (1 - INH) - KOUT * R;

$CAPTURE CP
'
pkpd_model <- simtte::tte_model(model = pkpd_code,
  hazard = "H0 * (R / (KIN / KOUT))", params = list(H0 = 0.15),
  name = "postcard_pkpd_hazard")

# ---------------------------------------------------------------------------
# Constants -- postcard's own real values (pkpd_power_00_setup.R's
# `constants` list), smoke-reduced only where marked SMOKE below.
# ---------------------------------------------------------------------------
end   <- 24    # months follow-up
delta <- 0.1   # output grid step (months)
ii    <- 1     # dosing interval (months; once-monthly subcut)
addl  <- 23    # additional doses (24 total)
alpha <- 0.05

# SMOKE: 2 small sample sizes, 4 replicates -- a local sanity check, not a
# real power estimate. FULL: the postcard's own real values -- 5 sample
# sizes up to 400/arm, 500 replicates -- a genuinely heavy HPC-scale run
# (3 dose scenarios x 5 sample sizes x 500 replicates = 7,500 full
# two-arm simulations; the postcard itself only ever ran 1,500 full
# cohorts, reusing each via nested subsetting at 5 sample sizes --
# simttepower deliberately does not do that, see README.md "Sample size:
# an ordinary grid factor, not nested subsetting").
if (smoke) {
  sample_sizes <- c(20L, 40L)
  n_sims <- 4L
  n_chunks <- 2L
} else {
  sample_sizes <- c(25L, 50L, 100L, 200L, 400L)
  n_sims <- 500L
  n_chunks <- 50L
}

# ---------------------------------------------------------------------------
# Dose-contrast scenarios (postcard's own 3 named contrasts)
# ---------------------------------------------------------------------------
dose_contrasts <- list(
  low_vs_std   = c(comparator = 10,  experimental = 100),
  std_vs_boost = c(comparator = 100, experimental = 200),
  std_vs_high  = c(comparator = 100, experimental = 400)
)

.dosing <- function(amt, n) {
  data.frame(ID = seq_len(n), time = 0, amt = amt, cmt = 1, evid = 1,
    ii = ii, addl = addl)
}

# Two real API frictions, both worked around explicitly here (never
# silently) -- see README.md "API friction and findings" 1-2 for the full
# write-up and the exact commands used to confirm each:
#
# 1. scenario_grid()'s `over` varies exactly one (arm, field) pair per
#    entry and crosses multiple entries independently (expand.grid()-
#    style) -- it has no "these two fields move together" mode. A dose
#    contrast here means comparator AND experimental dose changing
#    together (not independently), so it can't be one `over` spec.
# 2. Varying `n` via `over` while an arm also declares a fixed `data`
#    (dosing events) is unsafe: confirmed directly, sim_tte_ode() ties
#    subject count to `data`'s own row count whenever `data` is
#    narrower than `n` (n = 40 with a 20-row `data`: silently returns
#    20 subjects, no warning), and errors opaquely ("ID found in the
#    data set, but not in idata") whenever `data` is wider than `n`. So
#    `n` and `data` must be built as an already-matched pair, never
#    varied independently.
#
# Both are solved the same way: build every (dose contrast x sample
# size) combination as its own one-row scenario_grid() call (`n` and
# `data` always matching for that row), then rbind() all of them into
# one grid, reassigning scenario_id so the combined grid still
# identifies each row uniquely.
grid_pieces <- list()
for (scn_id in names(dose_contrasts)) {
  amt <- dose_contrasts[[scn_id]]
  for (n in sample_sizes) {
    comparator <- arm(label = "comparator", n = n, model = pkpd_model,
      end = end, delta = delta, data = .dosing(amt[["comparator"]], n))
    experimental <- arm(label = "experimental", n = n, model = pkpd_model,
      end = end, delta = delta, data = .dosing(amt[["experimental"]], n))

    design <- trial_design(
      arms = list(comparator, experimental),
      analyses = list(coxph = function(events) {
        analysis_coxph(events, formula = ~arm)
      })
    )

    # A single, non-null truth per scenario (any negative estimate; only
    # its *sign* matters to reject_direction()): higher dose is expected
    # protective for every one of these 3 contrasts (none is a null
    # scenario), matching the postcard's own power definition -- p <
    # alpha AND estimate < 0 (pkpd_power_03_aggregate.R's own `power`
    # column) is exactly reject_direction()'s contract.
    #
    # scenario_grid() requires a non-empty `over`; both arms' `n`/`data`
    # are already correctly matched above, so this one-value `n` entry
    # varies nothing new -- it exists to give the combined grid a real,
    # meaningful `n` column (used by plot_power(x = "n") later), not as
    # a workaround for the empty-`over` requirement.
    g <- scenario_grid(design, over = list(arm = "experimental",
      field = "n", values = n), truth = function(v) {
      c(estimate_armexperimental = -0.001)
    })
    g$dose_contrast <- scn_id
    grid_pieces[[length(grid_pieces) + 1L]] <- g
  }
}

grid <- do.call(rbind, grid_pieces)
grid$scenario_id <- paste0("s", seq_len(nrow(grid)))
for (i in seq_len(nrow(grid))) grid$scenario[[i]]$scenario_id <- grid$scenario_id[i]
rownames(grid) <- NULL
class(grid) <- class(grid_pieces[[1]])

cat(sprintf("[plan] %s config: %d dose contrast(s) x %d sample size(s) x %d replicate(s) = %d tasks\n",
  if (smoke) "SMOKE" else "FULL", length(dose_contrasts), length(sample_sizes),
  n_sims, nrow(grid) * n_sims))

# ---------------------------------------------------------------------------
# Write the manifest -- no simulation runs here.
# ---------------------------------------------------------------------------
manifest <- power_sim_chunks(grid, n_sims = n_sims, seed = 20260101,
  reject = reject_direction, n_chunks = n_chunks, dir = work_dir)

cat(sprintf("[plan] Manifest written to %s (%d chunks)\n", work_dir, n_chunks))
cat(sprintf("[plan] Next: run 01_worker.R for chunks 1..%d (array job, or a\n",
  n_chunks))
cat("[plan] loop for a local check), then 02_merge_report.R.\n")
cat(sprintf("[plan] POSTCARD_WORK_DIR=%s\n", work_dir))
