# Small, shared fixtures. Kept tiny (n ~10-20, end ~12) so the whole fast
# suite stays fast -- these still exercise sim_tte_ode(), so the very
# first test in a session pays a one-time mrgsolve model-build cost.

.test_param <- function(IC50 = 1) {
    list(CL = 2, V2 = 20, KA = 1, KIN = 1, KOUT = 0.5, IC50 = IC50,
        IMAX = 0.9, H0 = 0.15)
}

.test_arm <- function(label, n = 10, end = 12, IC50 = 1, ...) {
    arm(label = label, n = n, model = "irm1_hazard", end = end,
        param = .test_param(IC50), ...)
}

.test_design <- function(n = 10, end = 12, ic50_experimental = 1,
    analyses = list(coxph = analysis_coxph)) {
    trial_design(
        arms = list(
            .test_arm("comparator", n = n, end = end),
            .test_arm("experimental", n = n, end = end, IC50 = ic50_experimental)
        ),
        analyses = analyses
    )
}

# One comparator + one experimental arm's simulated events, rbind'd and
# labeled the way power_sim()'s own engine does internally -- used by
# analysis-function tests that need events without running the full engine.
.two_arm_events <- function() {
    e1 <- simtte::sim_tte_ode(model = "irm1_hazard", n = 15, end = 12,
        param = .test_param(), seed = 11)$events
    e2 <- simtte::sim_tte_ode(model = "irm1_hazard", n = 15, end = 12,
        param = .test_param(IC50 = 4), seed = 12)$events
    e1$arm <- "comparator"
    e2$arm <- "experimental"
    ev <- rbind(e1, e2)
    ev$arm <- factor(ev$arm, levels = c("comparator", "experimental"))
    ev
}
