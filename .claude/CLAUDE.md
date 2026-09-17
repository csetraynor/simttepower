# simttepower — agent working rules

Companion package to `simtte`: trial replication and simulation-based
power / operating-characteristic analysis on top of simtte's
single-cohort simulator.

## Git / GitHub

- **Never run** `git commit`, `git push`, `git merge`, `git rebase`,
  `git tag`, or any other history-changing command. The author does all
  commits and pushes.
- Leave changes in the working tree and list changed files in the
  session's report; do not stage or commit them yourself.
- Branch model: `dev` for work in progress, `main` for release. CRAN
  submissions are cut from `main`. Tags mark released versions only.
- The dev-only `Remotes: csetraynor/simtte` entry in `DESCRIPTION` (for
  installing simtte from GitHub pre-CRAN) must be removed before any
  release.
- `reports/`, `dev/`, and generated artefacts (`README.html`,
  `README-*.png` outside `man/figures/`) stay untracked/ignored — never
  add them to git.

## Working conventions

- **Plan before building.** Every phase starts with a design/plan report
  in `reports/` for the author to review before implementation begins.
- All plans, audits, and reports are Markdown in `reports/` (already
  build- and git-ignored).
- Nothing is committed by the agent, ever (see Git section above).
- **Ponytail**: `/ponytail-audit` on a plan/design before any code exists
  (keep proposed scope lean, flag over-building early); `/ponytail-review`
  on every code diff. Applies to code, not to reports/tests/docs.
- **ihaveadhd**: every phase report gets a short TL;DR at the top,
  generated with the `ihaveadhd` skill (not hand-written), mirroring the
  `*_simple.md` companions used in the simtte project.
- Fast/slow test split via `SIMTTEPOWER_SLOW_TESTS` (see
  `dev/run-tests.R`); `skip_on_cran()` on anything slow or parallel. A
  bare `R CMD check` skips slow tests silently (the env var is never
  set) -- always check via `Rscript dev/run-tests.R --check`.
  **No test or example may spawn more than 2 workers** (CRAN policy).
- `survival` and `ggplot2` stay in `Suggests`, guarded with
  `requireNamespace()` / `skip_if_not_installed()`. The only hard
  dependency beyond base R is `simtte` (plus `parallel`, base).
- **Never reach into simtte internals with `:::`.** Use only simtte's
  exported API (see `reports/00_simtte_api.md`). If something needed is
  not exported, list it as a gap for the author to add to `simtte` --
  do not work around it.
