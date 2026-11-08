sha256 <- function(path) digest::digest(file = path, algo = "sha256")

write_json <- function(value, path) {
  jsonlite::write_json(value, path, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
}

code_fingerprint <- function() {
  modules <- setdiff(list.files("R", pattern = "\\.R$", full.names = TRUE), "R/site.R")
  paths <- sort(c(modules, "R/models/elo_tuning.R", "scripts/pipeline.R", "renv.lock"))
  if (length(paths) < 3L || !all(file.exists(paths))) stop("Run from the repository root to record code provenance")
  as.list(setNames(vapply(paths, sha256, character(1)), paths))
}

replace_directory <- function(output, write) {
  dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
  backup <- paste0(output, ".previous")
  if (dir.exists(backup)) stop("Previous output needs recovery: ", backup)
  staging <- tempfile("stage-", tmpdir = dirname(output))
  dir.create(staging)
  on.exit(unlink(staging, recursive = TRUE), add = TRUE)
  value <- write(staging)
  if (dir.exists(output) && !file.rename(output, backup)) stop("Cannot preserve previous output")
  if (!file.rename(staging, output)) {
    if (dir.exists(backup)) file.rename(backup, output)
    stop("Cannot replace output directory")
  }
  unlink(backup, recursive = TRUE)
  invisible(value)
}

prepare_data <- function(raw_dir, output, as_of, require_fresh = FALSE, coverage = formats) {
  data <- load_matches(raw_dir, as_of, require_fresh, coverage)
  if (!setequal(unique(data$matches$format), coverage$format)) stop("Missing a format in prepared data")
  replace_directory(output, function(directory) {
    readr::write_csv(data$matches, file.path(directory, "matches.csv"), na = "")
    manifest <- list(
      schema_version = 1L, as_of = as.character(as_of),
      match_counts = as.list(table(data$matches$format)),
      last_result = lapply(split(data$matches$end_date, data$matches$format), function(dates) as.character(max(dates))),
      outcome_counts = as.list(table(data$matches$result)), sources = data$sources,
      matches_sha256 = sha256(file.path(directory, "matches.csv")), code_sha256 = code_fingerprint()
    )
    write_json(manifest, file.path(directory, "manifest.json"))
    manifest
  })
}

read_prepared <- function(directory) {
  manifest <- jsonlite::read_json(file.path(directory, "manifest.json"), simplifyVector = FALSE)
  path <- file.path(directory, "matches.csv")
  if (!identical(sha256(path), manifest$matches_sha256)) stop("Prepared data checksum mismatch")
  matches <- readr::read_csv(path, col_types = readr::cols(
    match_id = readr::col_integer(), format = readr::col_character(),
    start_date = readr::col_date(), end_date = readr::col_date(),
    team1_id = readr::col_integer(), team1 = readr::col_character(),
    team2_id = readr::col_integer(), team2 = readr::col_character(),
    result = readr::col_character(), score = readr::col_double(), source_url = readr::col_character()
  ), show_col_types = FALSE)
  if (nrow(readr::problems(matches))) stop("Invalid prepared data types")
  if (anyDuplicated(matches$match_id)) stop("Duplicate prepared match IDs")
  if (any(matches$end_date > as.Date(manifest$as_of))) stop("Prepared data exceed cutoff")
  list(matches = as.data.frame(matches), manifest = manifest)
}

analyze_data <- function(input, output, model = "elo", k = NULL) {
  if (model != "elo") stop("No verified pipeline adapter for model: ", model)
  data <- read_prepared(input)
  as_of <- as.Date(data$manifest$as_of)
  selected <- if (is.null(k)) select_production_elo_k(data$matches, as_of) else NULL
  if (!is.null(selected)) k <- selected$k
  result <- calculate_elo(data$matches, as_of, k = k, selection = selected$specification)
  replace_directory(output, function(directory) {
    for (name in c("latest", "monthly", "updates")) {
      readr::write_csv(result[[name]], file.path(directory, paste0(name, ".csv")), na = "")
    }
    if (!is.null(selected)) {
      readr::write_csv(selected$selections, file.path(directory, "k_selection.csv"))
      readr::write_csv(selected$curves, file.path(directory, "k_tuning.csv"))
    }
    saveRDS(result$models, file.path(directory, "fits.rds"))
    files <- list.files(directory, pattern = "[.]csv$", full.names = TRUE)
    metadata <- list(
      model = model, as_of = data$manifest$as_of,
      input_sha256 = data$manifest$matches_sha256, specification = result$specification,
      last_result = lapply(split(data$matches$end_date, data$matches$format), function(dates) as.character(max(dates))),
      r_version = as.character(getRversion()),
      code_sha256 = code_fingerprint(),
      files = as.list(setNames(vapply(files, sha256, character(1)), basename(files)))
    )
    write_json(metadata, file.path(directory, "manifest.json"))
    metadata
  })
}

read_analysis <- function(directory) {
  manifest <- jsonlite::read_json(file.path(directory, "manifest.json"), simplifyVector = FALSE)
  for (name in names(manifest$files)) {
    if (!identical(sha256(file.path(directory, name)), manifest$files[[name]])) {
      stop("Analysis checksum mismatch: ", name)
    }
  }
  read <- function(name) {
    readr::read_csv(file.path(directory, paste0(name, ".csv")),
      col_types = readr::cols(), show_col_types = FALSE
    )
  }
  list(manifest = manifest, latest = read("latest"), monthly = read("monthly"), updates = read("updates"))
}

visualize_data <- function(input, output) {
  data <- read_analysis(input)
  styles <- chart_styles(data$latest)
  replace_directory(output, function(directory) {
    for (format in unique(data$latest$format)) {
      charts <- ratings_charts(data, format, styles)
      for (view in names(charts)) {
        stem <- paste0(tolower(format), if (view == "history") "_history" else "")
        height <- if (view == "history") 12 else 7
        ggplot2::ggsave(file.path(directory, paste0(stem, ".png")), charts[[view]],
          width = 12, height = height, dpi = 180, bg = "white"
        )
        ggplot2::ggsave(file.path(directory, paste0(stem, ".svg")), charts[[view]],
          device = grDevices::svg, width = 12, height = height, bg = "white"
        )
      }
    }
    manifest <- list(
      analysis_sha256 = sha256(file.path(input, "manifest.json")),
      code_sha256 = code_fingerprint(),
      files = as.list(setNames(
        vapply(list.files(directory, full.names = TRUE), sha256, character(1)),
        list.files(directory)
      ))
    )
    write_json(manifest, file.path(directory, "manifest.json"))
    manifest
  })
}

write_report <- function(data, path) {
  lines <- c(
    paste0("# ", toupper(data$manifest$model), " cricket ratings through ", data$manifest$as_of), "",
    "Independent ratings of men's international teams. Results enter on their completion date.", "",
    "[Latest ratings](latest.csv) · [Monthly history](monthly.csv) · [Match updates](updates.csv)", "",
    "[Methods and limitations](../../../docs/pipeline.md#elo-specification)", ""
  )
  for (format in unique(data$latest$format)) {
    rows <- data$latest[data$latest$format == format & data$latest$is_active, ]
    label <- paste0(rows$team, ifelse(rows$is_provisional, " (provisional)", ""))
    lines <- c(
      lines, paste0("## ", format), "",
      paste("Most recent recorded result:", data$manifest$last_result[[format]]), "",
      paste("K:", data$manifest$specification$k[[format]]), "",
      paste0("![", format, " recent rating history](", tolower(format), ".png)"), "",
      paste0("[Download recent-history SVG](", tolower(format), ".svg)"), "",
      "<details>", "<summary>Full history by team</summary>", "",
      paste0("![", format, " full rating histories](", tolower(format), "_history.png)"), "",
      paste0("[Download full-history SVG](", tolower(format), "_history.svg)"), "",
      "</details>", "", "### Current ratings", "",
      "| Rank | Team | Rating | Rated matches | Last rated match |",
      "| ---: | --- | ---: | ---: | --- |",
      sprintf("| %s | %s | %s | %s | %s |", rows$rank, label, rows$rating, rows$rated_matches, rows$last_rated_match),
      ""
    )
  }
  writeLines(head(lines, -1L), path, useBytes = TRUE)
}

publish_data <- function(prepared, analysis, figures, output, require_fresh = TRUE, now = Sys.time()) {
  source <- read_prepared(prepared)
  data <- read_analysis(analysis)
  if (
    !identical(source$manifest$matches_sha256, data$manifest$input_sha256) ||
      !identical(source$manifest$as_of, data$manifest$as_of)
  ) {
    stop("Analysis uses different prepared data")
  }
  visual <- jsonlite::read_json(file.path(figures, "manifest.json"), simplifyVector = FALSE)
  code <- code_fingerprint()
  for (manifest in list(source$manifest, data$manifest, visual)) {
    if (!identical(manifest$code_sha256, code)) stop("Stage code differs; rebuild all stages before publication")
  }
  if (!identical(visual$analysis_sha256, sha256(file.path(analysis, "manifest.json")))) {
    stop("Figures use different analysis")
  }
  for (name in names(visual$files)) {
    if (!identical(sha256(file.path(figures, name)), visual$files[[name]])) stop("Figure checksum mismatch")
  }
  if (require_fresh) {
    age <- as.integer(as.Date(now, tz = "UTC") - as.Date(data$manifest$as_of))
    if (is.na(age) || age < 1L || age > 8L) stop("Publication cutoff is stale or incomplete")
    for (receipt in source$manifest$sources) {
      validate_source_freshness(receipt, as.Date(data$manifest$as_of), now)
    }
  }
  replace_directory(output, function(directory) {
    inputs <- c(
      file.path(analysis, names(data$manifest$files)),
      file.path(figures, names(visual$files))
    )
    if (!all(file.copy(inputs, directory))) stop("Cannot stage publication")
    write_report(data, file.path(directory, "index.md"))
    manifest <- list(
      analysis = data$manifest, source = source$manifest, visualization = visual,
      code_sha256 = code_fingerprint(),
      files = as.list(setNames(
        vapply(list.files(directory, full.names = TRUE), sha256, character(1)),
        list.files(directory)
      ))
    )
    write_json(manifest, file.path(directory, "manifest.json"))
    manifest
  })
}
