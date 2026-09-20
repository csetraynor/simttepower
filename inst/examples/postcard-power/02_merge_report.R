#!/usr/bin/env Rscript
# =============================================================================
# 02_merge_report.R -- combine chunks, summarise, and plot.
# =============================================================================
# Run locally, once every chunk_<i>.rds from 01_worker.R is present (see
# this example's README.md for how to tell). Reproduces
# ../simtte_postcard/scripts/pkpd_power_03_aggregate.R's own two outputs --
# a results table and a power-curve figure -- on the current API.
#
# Inputs:  <work_dir>/manifest.rds, <work_dir>/chunk_*.rds
# Outputs: <work_dir>/power_summary.csv
#          <work_dir>/power_curves.png (only if ggplot2 is installed)
#
# Usage:   Rscript 02_merge_report.R
# Runtime: seconds -- this step does no simulation, only combines and
#          summarises what 01_worker.R already wrote.
# =============================================================================

suppressPackageStartupMessages(library(simttepower))

work_dir <- Sys.getenv("POSTCARD_WORK_DIR",
  file.path(tempdir(), "postcard-power-work"))

res <- power_sim_merge(work_dir)
s <- summary(res)

cat("[report] Power summary:\n")
print(as.data.frame(s), row.names = FALSE)

# power/type_I_error, from oc_label: every scenario here declared a
# non-null truth (see 00_plan.R), so every row should read "power" --
# printed as a sanity check, not because a null scenario is expected.
cat("\n[report] oc_label distribution:\n")
print(table(s$oc_label, useNA = "ifany"))

# Minimum-N table (80%/90% power), matching pkpd_power_03_aggregate.R's
# own n_table -- postcard's own convention, reproduced directly.
n_threshold <- function(power_vec, n_vec, threshold) {
  idx <- which(power_vec >= threshold)
  if (!length(idx)) return(NA_integer_)
  n_vec[which.min(n_vec[idx])]
}
n_table <- do.call(rbind, lapply(split(s, s$dose_contrast), function(d) {
  data.frame(dose_contrast = d$dose_contrast[1],
    N_80pct = n_threshold(d$reject_rate, d$n, 0.80),
    N_90pct = n_threshold(d$reject_rate, d$n, 0.90))
}))
cat("\n[report] Minimum sample size (per arm) for 80%/90% power")
cat(" (SMOKE config: not a real estimate, too few replicates):\n")
print(n_table, row.names = FALSE)

summary_path <- file.path(work_dir, "power_summary.csv")
write.csv(as.data.frame(s), summary_path, row.names = FALSE)
cat(sprintf("\n[report] Wrote %s\n", summary_path))

if (requireNamespace("ggplot2", quietly = TRUE)) {
  p <- plot_power(s, x = "n", color = "dose_contrast") +
    ggplot2::labs(title = "PK/PD dose-response power (postcard reproduction)",
      x = "Sample size (N per arm)", colour = "Dose contrast")
  fig_path <- file.path(work_dir, "power_curves.png")
  ggplot2::ggsave(fig_path, p, width = 8, height = 5.5, dpi = 150)
  cat(sprintf("[report] Wrote %s\n", fig_path))
} else {
  cat("[report] ggplot2 not installed -- skipped power_curves.png.\n")
}

cat("\n[report] === DONE ===\n")
