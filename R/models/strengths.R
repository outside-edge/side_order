quarter_date <- function(index) {
  as.Date(sprintf("%04d-%02d-01", index %/% 4L, (index %% 4L) * 3L + 1L))
}

export_model_strengths <- function(spline, stan, train, origin, output, current = FALSE) {
  teams <- latest_team_labels(train)
  quarters <- seq(min(quarter_index(train$start_date)), quarter_index(origin))
  dates <- quarter_date(quarters)
  dates <- sort(unique(c(dates[dates >= min(train$start_date)], as.Date(origin))))
  covariance <- vcov(spline$model, unconditional = TRUE)
  gam <- do.call(rbind, lapply(as.list(dates), function(date) {
    grid <- train[rep(1L, nrow(teams)), ]
    grid$team1_id <- teams$team_id
    grid$team2_id <- teams$team_id[1]
    grid$start_date <- pmin(date, spline$last_date)
    grid$home_sign <- 0
    design <- predict(spline$model, newdata = gam_inputs(grid, spline$levels, spline$margin), type = "lpmatrix")
    design <- sweep(design, 2, colMeans(design))
    estimate <- drop(design %*% coef(spline$model))
    se <- sqrt(pmax(0, rowSums((design %*% covariance) * design)))
    data.frame(
      model = "gam", date = date, teams, strength = estimate,
      lower = estimate - qnorm(0.95) * se, upper = estimate + qnorm(0.95) * se,
      interpretation = if (date < origin) "retrospective at origin" else "boundary forecast"
    )
  }))
  summary <- stan$fit$summary(variables = "skill")
  indices <- strcapture("skill\\[([0-9]+),([0-9]+)\\]", summary$variable, list(team = integer(), quarter = integer()))
  ids <- stan$inputs$levels$team[indices$team]
  dates <- quarter_date(stan$inputs$levels$quarter[indices$quarter])
  dynamic <- data.frame(
    model = "stan_dynamic_probit", date = dates, team_id = ids, team = teams$team[match(ids, teams$team_id)],
    strength = summary$mean, lower = summary$q5, upper = summary$q95,
    interpretation = ifelse(dates < origin, "retrospective at origin", "forecast")
  )
  first <- tapply(c(train$start_date, train$start_date), c(train$team1_id, train$team2_id), min)
  strengths <- rbind(gam, dynamic)
  if (current) {
    strengths$interpretation <- "retrospective at cutoff"
    latest <- (strengths$model == "gam" & strengths$date == origin) |
      (strengths$model == "stan_dynamic_probit" & quarter_index(strengths$date) == quarter_index(origin))
    strengths$interpretation[latest] <- "current estimate"
  }
  strengths <- strengths[as.numeric(strengths$date) >= first[as.character(strengths$team_id)], ]
  readr::write_csv(strengths, file.path(output, "strengths.csv"))
  invisible(strengths)
}

plot_model_strengths <- function(path) {
  .data <- rlang::.data
  strengths <- readr::read_csv(file.path(path, "strengths.csv"), show_col_types = FALSE)
  manifest <- jsonlite::read_json(file.path(path, "manifest.json"), simplifyVector = TRUE)
  if (!isTRUE(manifest$stan_diagnostics_passed)) stop("Cannot visualize a failed model run")
  for (name in names(manifest$outputs)) {
    if (digest::digest(file = file.path(path, name), algo = "sha256") != manifest$outputs[[name]]) {
      stop("Model output checksum mismatch: ", name)
    }
  }
  origin <- as.Date(manifest$origin)
  destination <- file.path("figs/models", tolower(manifest$format), manifest$origin)
  replace_directory(destination, function(destination) {
    for (name in unique(strengths$model)) {
      data <- strengths[strengths$model == name & strengths$date >= origin - 10L * 365L, ]
      plot <- ggplot2::ggplot(data, ggplot2::aes(x = .data$date, y = .data$strength)) +
        ggplot2::geom_hline(yintercept = 0, color = "grey75", linewidth = 0.3) +
        ggplot2::geom_vline(xintercept = origin, linetype = "dotted", color = "grey40") +
        ggplot2::geom_ribbon(ggplot2::aes(ymin = .data$lower, ymax = .data$upper), fill = "#0072B2", alpha = 0.16) +
        ggplot2::geom_line(color = "#0072B2", linewidth = 0.55) +
        ggplot2::facet_wrap(ggplot2::vars(.data$team), ncol = 3) +
        ggplot2::scale_x_date(date_breaks = "4 years", date_labels = "%Y") +
        ggplot2::labs(
          title = paste(manifest$format, "team strength:", if (name == "gam") "paired splines" else "dynamic probit"),
          subtitle = paste("Fit uses matches completed before", origin, "• shaded bands: 90% intervals"),
          x = NULL, y = if (name == "gam") "Relative strength (logistic scale)" else "Relative strength (probit scale)",
          caption = paste(
            "Experimental. Countries have separate panels; zero is the fitted-team mean.",
            "History is retrospective; dotted line marks the forecast origin.\n",
            if (name == "gam") {
              "GAM intervals include approximate smoothing-parameter uncertainty; forecasts hold the boundary."
            } else {
              "Stan intervals describe latent strength; forecast uncertainty grows through the held-out year."
            }
          )
        ) +
        ggplot2::theme_minimal(base_size = 12) +
        ggplot2::theme(panel.grid.minor = ggplot2::element_blank(), plot.caption = ggplot2::element_text(hjust = 0))
      ggplot2::ggsave(file.path(destination, paste0(name, ".png")), plot, width = 11, height = 9, dpi = 160)
      ggplot2::ggsave(file.path(destination, paste0(name, ".svg")), plot,
        width = 11, height = 9, device = grDevices::svg
      )
    }
  })
  invisible(destination)
}
