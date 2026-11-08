read_current_analysis <- function(path) {
  manifest <- jsonlite::read_json(file.path(path, "manifest.json"), simplifyVector = TRUE)
  if (!isTRUE(manifest$stan_diagnostics_passed)) stop("Cannot publish failed current models")
  if (!all(c("latest.csv", "strengths.csv", "coverage.csv", "stan_diagnostics.json") %in% names(manifest$outputs))) {
    stop("Incomplete current model outputs")
  }
  for (name in names(manifest$outputs)) {
    if (basename(name) != name || !file.exists(file.path(path, name))) stop("Missing current model output: ", name)
    if (digest::digest(file = file.path(path, name), algo = "sha256") != manifest$outputs[[name]]) {
      stop("Current model checksum mismatch: ", name)
    }
  }
  latest <- readr::read_csv(file.path(path, "latest.csv"), show_col_types = FALSE)
  required <- c("gam", "stan_dynamic_probit", "glicko2", "trueskill")
  if (!setequal(unique(latest$model), required) || anyDuplicated(latest[c("model", "team_id")])) {
    stop("Incomplete or duplicate current model ratings")
  }
  if (!nrow(latest) || anyNA(latest$as_of) || any(latest$as_of != as.Date(manifest$as_of))) {
    stop("Inconsistent current model cutoff")
  }
  list(manifest = manifest, latest = latest)
}

plot_current_models <- function(format = "Test") {
  .data <- rlang::.data
  input <- file.path("out/analysis/current", tolower(format))
  result <- read_current_analysis(input)
  labels <- c(gam = "GAM", stan_dynamic_probit = "Stan", glicko2 = "Glicko-2", trueskill = "TrueSkill")
  destination <- file.path("figs/models/current", tolower(format))
  replace_directory(destination, function(destination) {
    for (model in names(labels)) {
      rows <- result$latest[result$latest$model == model, ]
      rows$team <- factor(rows$team, levels = rows$team[order(rows$estimate)])
      plot <- ggplot2::ggplot(rows, ggplot2::aes(y = .data$team, x = .data$estimate)) +
        ggplot2::geom_segment(ggplot2::aes(x = .data$lower, xend = .data$upper, yend = .data$team),
          color = "#0072B2", linewidth = 0.6
        ) +
        ggplot2::geom_point(ggplot2::aes(shape = .data$is_active), color = "#0072B2", size = 2.5) +
        ggplot2::scale_shape_manual(values = c("TRUE" = 16, "FALSE" = 1), guide = "none") +
        ggplot2::labs(
          title = paste(format, "ratings:", labels[[model]]),
          subtitle = paste("Completed matches through", result$manifest$as_of),
          x = paste(labels[[model]], "strength (model-specific scale)"), y = NULL,
          caption = "Points: strength estimates; lines: 90% intervals. Hollow points: inactive teams."
        ) +
        ggplot2::theme_minimal(base_size = 12) +
        ggplot2::theme(panel.grid.minor = ggplot2::element_blank(), plot.caption = ggplot2::element_text(hjust = 0))
      height <- max(5, 1.5 + 0.25 * nrow(rows))
      ggplot2::ggsave(file.path(destination, paste0(model, ".png")), plot, width = 8, height = height, dpi = 160)
      ggplot2::ggsave(file.path(destination, paste0(model, ".svg")), plot,
        width = 8, height = height,
        device = grDevices::svg
      )
    }
    files <- list.files(destination, full.names = TRUE)
    jsonlite::write_json(list(
      analysis_sha256 = digest::digest(file = file.path(input, "manifest.json"), algo = "sha256"),
      files = setNames(lapply(files, digest::digest, algo = "sha256", file = TRUE), basename(files))
    ), file.path(destination, "manifest.json"), auto_unbox = TRUE, pretty = TRUE)
  })
  invisible(destination)
}

publish_current_models <- function(format = "Test") {
  input <- file.path("out/analysis/current", tolower(format))
  figures <- file.path("figs/models/current", tolower(format))
  analysis <- read_current_analysis(input)
  for (path in names(analysis$manifest$hashes)) {
    if (!file.exists(path) || digest::digest(file = path, algo = "sha256") != analysis$manifest$hashes[[path]]) {
      stop("Current model inputs or code changed; refit before publication: ", path)
    }
  }
  charts <- jsonlite::read_json(file.path(figures, "manifest.json"), simplifyVector = TRUE)
  required <- as.vector(outer(c("gam", "stan_dynamic_probit", "glicko2", "trueskill"), c(".png", ".svg"), paste0))
  if (!all(required %in% names(charts$files))) stop("Incomplete current model figures")
  if (charts$analysis_sha256 != digest::digest(file = file.path(input, "manifest.json"), algo = "sha256")) {
    stop("Current model figures do not match analysis")
  }
  for (name in names(charts$files)) {
    checksum <- digest::digest(file = file.path(figures, name), algo = "sha256")
    if (basename(name) != name || checksum != charts$files[[name]]) {
      stop("Current model figure checksum mismatch: ", name)
    }
  }
  output <- file.path("out/release/models", tolower(format))
  replace_directory(output, function(output) {
    files <- c(
      file.path(input, names(analysis$manifest$outputs)), file.path(figures, names(charts$files))
    )
    if (!all(file.copy(files, output))) stop("Cannot copy current model publication")
    manifest <- analysis$manifest
    manifest$files <- c(manifest$outputs, charts$files)
    manifest$outputs <- NULL
    jsonlite::write_json(manifest, file.path(output, "manifest.json"), auto_unbox = TRUE, pretty = TRUE)
  })
  invisible(output)
}
