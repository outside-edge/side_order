args <- commandArgs(trailingOnly = TRUE)
commands <- c("fetch", "prepare", "analyze", "visualize", "publish", "update")
if (!length(args) || !args[1] %in% commands) {
  stop("Usage: Rscript scripts/pipeline.R <fetch|prepare|analyze|visualize|publish|update> [YYYY-MM-DD] [--refresh]")
}
command <- args[1]
refresh <- "--refresh" %in% args
rest <- args[-1][args[-1] != "--refresh"]
if (length(rest) > 1L || (length(rest) && !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", rest))) stop("Invalid arguments")
if (length(rest) && command %in% c("analyze", "visualize", "publish")) {
  stop("This stage inherits its cutoff from prepared data; use prepare to change the date")
}
today <- as.Date(Sys.time(), tz = "UTC")
as_of <- if (length(rest)) as.Date(rest) else today - 1L
if (is.na(as_of) || as_of >= today) stop("Cutoff must be a completed UTC calendar day")
source("R/paths.R")
source("R/acquisition.R")
source("R/elo.R")
source("R/visualization.R")
source("R/pipeline.R")
source("R/models/elo_tuning.R")
if (command %in% c("fetch", "update")) fetch_sources(pipeline_paths$raw, as_of, refresh)
if (command %in% c("prepare", "update")) {
  prepare_data(pipeline_paths$raw, pipeline_paths$matches, as_of, command == "update")
}
if (command %in% c("analyze", "update")) analyze_data(pipeline_paths$matches, pipeline_paths$analysis)
if (command %in% c("visualize", "update")) visualize_data(pipeline_paths$analysis, pipeline_paths$figures)
if (command %in% c("publish", "update")) {
  publish_data(pipeline_paths$matches, pipeline_paths$analysis, pipeline_paths$figures, pipeline_paths$publication)
}
