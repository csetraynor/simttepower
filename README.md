
<!-- README.md is generated from README.Rmd. Please edit that file -->

# simttepower

<!-- badges: start -->

<!-- badges: end -->

simttepower is a companion to
[simtte](https://github.com/csetraynor/simtte), providing trial
replication and simulation-based power and operating-characteristic
analysis on top of simtte’s single-cohort PK/PD time-to-event simulator.
Given a trial design and a grid of scenarios that vary any one factor (a
model parameter, a formula coefficient, a dosing regimen, a sampling
schedule, sample size, follow-up, or covariate distribution),
simttepower replicates each scenario, applies one or more analysis
functions to each simulated trial, and summarises operating
characteristics – power, type I error, bias, coverage – across the grid.

## Installation

You can install the development version of simttepower from
[GitHub](https://github.com/) with:

``` r
# install.packages("pak")
pak::pak("csetraynor/simttepower")
```

## Example

Two arms of a built-in PK/PD hazard model, varying the nonlinear-link
`IC50` parameter on the experimental arm, replicated and summarised:

``` r
library(simttepower)

comparator <- arm(label = "comparator", n = 40, model = "irm1_hazard",
  end = 24, param = list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5,
    IC50 = 1, IMAX = 0.9, H0 = 0.15))
experimental <- arm(label = "experimental", n = 40, model = "irm1_hazard",
  end = 24, param = list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5,
    IC50 = 1, IMAX = 0.9, H0 = 0.15))

design <- trial_design(
  arms = list(comparator, experimental),
  analyses = list(coxph = analysis_coxph)
)

grid <- scenario_grid(design, over = list(arm = "experimental",
  field = "param.IC50", values = c(1, 2, 4)))

res <- power_sim(grid, n_sims = 5, seed = 1, progress = FALSE)
summary(res)
#> <simttepower_summary>
#>  scenario_id IC50 analysis n_sims reject_rate reject_se n_errors
#>           s1    1    coxph      5           0         0        0
#>           s2    2    coxph      5           0         0        0
#>           s3    4    coxph      5           0         0        0
#>  median_runtime_sec median_duration median_events_comparator
#>               0.039              24                       39
#>               0.032              24                       38
#>               0.033              24                       40
#>  median_events_experimental
#>                          38
#>                          39
#>                          39
```

See `vignette("power-analysis")` for a real dosing-regimen contrast, a
covariate-adjusted analysis, and a direction-aware rejection rule.

You’ll still need to render `README.Rmd` regularly, to keep `README.md`
up-to-date. `devtools::build_readme()` is handy for this.
