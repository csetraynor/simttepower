# simttepower (development version)

* Initial CRAN submission.
* A computed `cum_dose` column (total dose administered, attached to
  simulated events by the replication engine) was added during Phase 1
  development and removed before any release: not needed (groups are
  the `arm`/`regimen` labels; a numeric contrast exists only when the
  user declares `dose`) and wrong for `addl`/`ii` dosing regimens (one
  row with `addl = 11` counted as one dose). It never shipped in a
  release.
* `power_sim(workers > 1)`'s worker model-loading layer (added in Phase
  2) was reworked to build on simtte's own supported
  `simtte_prepare_model()`/`simtte_model_cache()` (simtte >= 1.1.0)
  instead of simttepower calling `mrgsolve::mcode_cache()`/`loadso()`
  directly. This removed: a retry loop worked around an intermittent
  worker-loading race (the race itself is gone by construction under
  the new loading path); global `options(mrgsolve.project =`
  `mrgsolve.soloc = )` calls (simttepower never sets a global mrgsolve
  option now); and simttepower's own model-cache directory (a model's
  compiled artifact is simtte's concern). `mrgsolve` was accordingly
  dropped from `Imports` (nothing in simttepower calls it directly any
  more). None of this ever shipped in a release.
