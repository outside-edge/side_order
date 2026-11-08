plot_elo_tuning <- function(format = NULL) {
  if (is.null(format)) format <- c("Test", "ODI", "T20I")
  if (!length(format) || any(!format %in% c("Test", "ODI", "T20I"))) stop("Unknown format")
  .data <- rlang::.data
  for (name in format) {
    input <- file.path("out/analysis/elo_tuning", tolower(name))
    manifest_path <- file.path(input, "manifest.json")
    manifest <- jsonlite::read_json(manifest_path)
    for (file in names(manifest$files)) {
      if (basename(file) != file || !identical(sha256(file.path(input, file)), manifest$files[[file]])) {
        stop("Tuning output checksum mismatch: ", file)
      }
    }
    curve <- readr::read_csv(file.path(input, "current_curve.csv"), show_col_types = FALSE)
    current <- readr::read_csv(file.path(input, "current_selection.csv"), show_col_types = FALSE)
    folds <- readr::read_csv(file.path(input, "folds.csv"), show_col_types = FALSE)
    folds <- folds[folds$window == current$window & folds$supported & folds$n_evaluation > 0L, ]
    curve$excess_mse <- curve$mse - min(curve$mse)
    selected <- curve[curve$k == current$selected_k, ]
    loss_curve <- ggplot2::ggplot(curve, ggplot2::aes(.data$k, .data$excess_mse)) +
      ggplot2::geom_hline(
        yintercept = manifest$specification$near_minimum_mse, linetype = "dashed", colour = "#777777"
      ) +
      ggplot2::geom_vline(xintercept = 100, linetype = "dotted", colour = "#777777") +
      ggplot2::geom_line(colour = "#173744", linewidth = 0.7) +
      ggplot2::geom_point(data = selected, size = 3, colour = "#173744") +
      ggplot2::scale_x_log10(breaks = c(1, 5, 10, 20, 50, 100, 200, 400)) +
      ggplot2::labs(
        title = paste(name, "expected-score error by K"),
        subtitle = sprintf(
          "Selection at %s: K = %s; preceding %d years, %d matches",
          current$origin, current$selected_k, current$window, current$n_tuning
        ),
        x = "K (logarithmic axis)", y = "Mean squared error above the minimum",
        caption = paste("Point: selected K. Vertical dotted line: fixed baseline K = 100.",
          "Horizontal dashed line: 0.001 MSE tolerance, not a confidence bound.",
          "Tuning scores; each forecast excludes results completed on or after match start.",
          sep = "\n"
        )
      ) +
      ratings_theme()
    folds$difference <- folds$tuned_mse - folds$baseline_mse
    annual <- ggplot2::ggplot(folds, ggplot2::aes(.data$year, .data$difference)) +
      ggplot2::geom_hline(yintercept = 0, colour = "#777777", linetype = "dashed") +
      ggplot2::geom_segment(ggplot2::aes(xend = .data$year, yend = 0), colour = "#173744") +
      ggplot2::geom_point(size = 2.5, colour = "#173744") +
      ggplot2::scale_x_continuous(breaks = folds$year) +
      ggplot2::labs(
        title = paste(name, "annual evaluation against K = 100"),
        subtitle = "Below zero favors the K selected using the preceding five years",
        x = "Match starting year", y = "Selected-policy MSE minus K = 100 MSE",
        caption = paste0(
          "Each year's K is selected before that year starts; ratings update between matches.\n",
          "Equal weight per match within each year. Retrospective evaluation through ", manifest$as_of,
          "; the final year may be partial.\n",
          "These are observed annual differences, not independent observations or confidence intervals."
        )
      ) +
      ratings_theme()
    output <- file.path("figs/elo_tuning", tolower(name))
    replace_directory(output, function(directory) {
      charts <- list(tuning_curve = loss_curve, annual_difference = annual)
      for (chart in names(charts)) {
        ggplot2::ggsave(file.path(directory, paste0(chart, ".png")), charts[[chart]],
          width = 11, height = 7, dpi = 180, bg = "white"
        )
        ggplot2::ggsave(file.path(directory, paste0(chart, ".svg")), charts[[chart]],
          device = grDevices::svg, width = 11, height = 7, bg = "white"
        )
      }
      files <- list.files(directory, full.names = TRUE)
      sources <- c("R/models/elo_tuning_plots.R", "R/visualization.R", "renv.lock")
      write_json(list(
        analysis_sha256 = sha256(manifest_path),
        code_sha256 = as.list(setNames(vapply(sources, sha256, character(1)), sources)),
        files = as.list(setNames(vapply(files, sha256, character(1)), basename(files)))
      ), file.path(directory, "manifest.json"))
    })
  }
  invisible(NULL)
}
