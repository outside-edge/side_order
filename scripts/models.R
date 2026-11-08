source("R/acquisition.R")
source("R/elo.R")
source("R/visualization.R")
source("R/pipeline.R")
for (module in list.files("R/models", pattern = "\\.R$", full.names = TRUE)) source(module)

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) {
  stop(
    "Usage: models.R prepare | resolve-venues | current [format] [iterations]",
    " | compare [format] [origin] [until] [iterations]",
    " | visualize <output-dir> | visualize-current [format] | publish-current [format]",
    " | tune-elo [format] | visualize-elo-tuning [format] | check-elo-tuning [format]"
  )
}
if (args[1] %in% c("tune-elo", "visualize-elo-tuning", "check-elo-tuning")) {
  if (length(args) > 2L) stop("Expected at most one format argument")
  format <- if (length(args) == 2L) args[2] else NULL
  if (args[1] == "tune-elo") {
    run_elo_tuning(format)
  } else if (args[1] == "visualize-elo-tuning") {
    plot_elo_tuning(format)
  } else {
    if (is.null(format)) format <- c("Test", "ODI", "T20I")
    if (any(!format %in% c("Test", "ODI", "T20I"))) stop("Unknown format")
    for (name in format) check_elo_tuning(file.path("out/analysis/elo_tuning", tolower(name)))
  }
} else if (args[1] == "prepare") {
  prepare_model_context()
} else if (args[1] == "resolve-venues" && length(args) == 1L) {
  prepare_model_venues()
} else if (args[1] == "current") {
  format <- if (length(args) >= 2L) args[2] else "Test"
  iterations <- if (length(args) >= 3L) as.integer(args[3]) else 1000L
  run_current_models(format, iterations)
} else if (args[1] == "publish-current") {
  publish_current_models(if (length(args) >= 2L) args[2] else "Test")
} else if (args[1] == "visualize-current") {
  plot_current_models(if (length(args) >= 2L) args[2] else "Test")
} else if (args[1] == "compare") {
  format <- if (length(args) >= 2L) args[2] else "Test"
  origin <- as.Date(if (length(args) >= 3L) args[3] else "2024-01-01")
  until <- as.Date(if (length(args) >= 4L) args[4] else "2025-01-01")
  iterations <- if (length(args) >= 5L) as.integer(args[5]) else 1000L
  run_model_comparison(format, origin, until, iterations)
} else if (args[1] == "visualize" && length(args) == 2L) {
  plot_model_strengths(args[2])
} else {
  stop("Unknown model command: ", args[1])
}
