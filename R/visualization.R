chart_teams <- function(latest, format_name) {
  teams <- latest[latest$format == format_name & latest$is_active, ]
  head(teams[order(-teams$rating, teams$team_id), ], 10)
}

chart_styles <- function(latest) {
  ids <- sort(unique(unlist(lapply(unique(latest$format), function(format) chart_teams(latest, format)$team_id))))
  colours <- grDevices::adjustcolor(
    grDevices::palette.colors(10, "Tableau 10"), red.f = 0.7, green.f = 0.7, blue.f = 0.7
  )
  list(
    colours = setNames(rep(colours, length.out = length(ids)), ids),
    lines = setNames(rep(rep(c("solid", "longdash", "dotdash"), each = 5), length.out = length(ids)), ids)
  )
}

chart_data <- function(latest, updates, format_name, start = NULL) {
  teams <- chart_teams(latest, format_name)
  if (!nrow(teams)) stop("No active rated teams to plot for ", format_name)
  updates <- updates[updates$format == format_name & updates$date <= max(teams$date), ]
  history <- do.call(rbind, lapply(1:2, function(side) {
    data.frame(
      team_id = updates[[paste0("team", side, "_id")]], date = updates$date,
      rating = updates[[paste0("team", side, "_after")]], sequence = seq_len(nrow(updates))
    )
  }))
  history <- history[history$team_id %in% teams$team_id, ]
  history <- history[order(history$date, history$sequence), ]
  history <- history[!duplicated(history[c("team_id", "date")], fromLast = TRUE), c("team_id", "date", "rating")]
  history <- rbind(history, teams[c("team_id", "date", "rating")])
  history <- history[!duplicated(history[c("team_id", "date")], fromLast = TRUE), ]
  if (!is.null(start)) {
    previous <- history[history$date <= start, ]
    previous <- previous[!duplicated(previous$team_id, fromLast = TRUE), ]
    previous$date <- rep(start, nrow(previous))
    history <- rbind(previous, history[history$date > start, ])
  }
  history <- history[order(history$date, history$team_id), ]
  history$format <- format_name
  history$team <- teams$team[match(history$team_id, teams$team_id)]
  panel_labels <- paste(teams$team, format(teams$rating, big.mark = ",", trim = TRUE), sep = "  ·  ")
  history$panel <- factor(history$team_id, levels = teams$team_id, labels = panel_labels)
  history
}

ratings_theme <- function() {
  ggplot2::theme_minimal(base_size = 13, base_family = "sans") +
    ggplot2::theme(
      text = ggplot2::element_text(colour = "#222222"),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_line(colour = "#E5E5E5", linewidth = 0.25),
      plot.title = ggplot2::element_text(face = "bold", size = 18),
      plot.subtitle = ggplot2::element_text(size = 12, margin = ggplot2::margin(b = 12)),
      plot.caption = ggplot2::element_text(hjust = 0, size = 10, margin = ggplot2::margin(t = 12)),
      plot.title.position = "plot", plot.caption.position = "plot",
      strip.text = ggplot2::element_text(face = "bold", hjust = 0, size = 12),
      legend.position = "none", plot.margin = ggplot2::margin(12, 18, 12, 12)
    )
}

ratings_charts <- function(data, format_name, styles = chart_styles(data$latest)) {
  .data <- rlang::.data
  teams <- chart_teams(data$latest, format_name)
  cutoff <- as.Date(data$manifest$as_of)
  start <- as.Date(paste0(as.integer(format(cutoff, "%Y")) - 9L, "-01-01"))
  history <- chart_data(data$latest, data$updates, format_name)
  recent <- chart_data(data$latest, data$updates, format_name, start)
  teams$label <- paste(teams$team, format(teams$rating, big.mark = ",", trim = TRUE), sep = "  ")
  note <- paste(
    "Current top ten active teams. Steps show end-of-day Elo; flat sections carry ratings forward.",
    "No smoothing or uncertainty intervals. Independent of ICC rankings.",
    sep = "\n"
  )
  comparison <- ggplot2::ggplot(recent, ggplot2::aes(
    x = .data$date, y = .data$rating, group = .data$team_id,
    colour = factor(.data$team_id), linetype = factor(.data$team_id)
  )) +
    ggplot2::geom_step(linewidth = 0.7, direction = "hv") +
    ggplot2::geom_point(data = teams, size = 2, show.legend = FALSE) +
    ggrepel::geom_text_repel(
      data = teams, ggplot2::aes(label = .data$label),
      colour = "#222222", size = 4.2, direction = "y", hjust = 0,
      nudge_x = 180, box.padding = 0.35, point.padding = 0.2,
      min.segment.length = 0, segment.colour = "#777777", segment.size = 0.3,
      seed = 42, max.overlaps = Inf, max.iter = 10000, max.time = Inf
    ) +
    ggplot2::scale_colour_manual(values = styles$colours) +
    ggplot2::scale_linetype_manual(values = styles$lines) +
    ggplot2::scale_x_date(
      breaks = seq(start, cutoff, by = "2 years"), date_labels = "%Y", limits = c(start, cutoff + 950),
      expand = ggplot2::expansion(mult = c(0.01, 0))
    ) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = 0.08)) +
    ggplot2::labs(
      title = paste(format_name, "Elo ratings"),
      subtitle = paste(
        "Recent history ·", format(start, "%Y"), "to", cutoff,
        "· K =", data$manifest$specification$k[[format_name]]
      ),
      x = NULL, y = "Elo rating", caption = note
    ) +
    ratings_theme()
  panels <- ggplot2::ggplot(history, ggplot2::aes(x = .data$date, y = .data$rating, group = .data$team_id)) +
    ggplot2::geom_step(colour = "#245673", linewidth = 0.5, direction = "hv") +
    ggplot2::facet_wrap(ggplot2::vars(.data$panel), ncol = 2, scales = "fixed") +
    ggplot2::scale_x_date(date_labels = "%Y", expand = ggplot2::expansion(mult = c(0.01, 0.02))) +
    ggplot2::labs(
      title = paste(format_name, "Elo ratings · full history"),
      subtitle = paste(
        "Current top ten active teams · through", cutoff,
        "· K =", data$manifest$specification$k[[format_name]]
      ),
      x = NULL, y = "Elo rating",
      caption = paste("All panels use the same axes. Headings give current ratings.", note, sep = "\n")
    ) +
    ratings_theme()
  list(recent = comparison, history = panels)
}
