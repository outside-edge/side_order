current_training <- function(matches, format, as_of, since = as.Date("2000-01-01")) {
  as_of <- as.Date(as_of)
  if (length(as_of) != 1L || is.na(as_of) || as_of < since) stop("Invalid rating cutoff")
  invitational <- c("ICC World XI", "World-XI", "Asia XI", "Africa XI")
  train <- matches[
    matches$format == format & matches$start_date >= since & matches$end_date <= as_of &
      !is.na(matches$score) & !matches$team1 %in% invitational & !matches$team2 %in% invitational,
  ]
  if (nrow(train) < 50L) stop("Insufficient data for current ratings")
  if (anyNA(train[c("country", "home_sign", "ground_profile_id")])) {
    stop("Current contextual ratings require complete venue coverage")
  }
  train[order(train$end_date, train$start_date, train$match_id), ]
}

current_teams <- function(train, as_of) {
  teams <- latest_team_labels(train)
  ids <- c(train$team1_id, train$team2_id)
  teams$rated_matches <- as.integer(table(ids)[as.character(teams$team_id)])
  last <- tapply(as.numeric(c(train$end_date, train$end_date)), ids, max)
  teams$last_rated_match <- as.Date(last[as.character(teams$team_id)], origin = "1970-01-01")
  teams$is_active <- teams$last_rated_match >= as_of - 730L
  teams$is_provisional <- teams$rated_matches < 10L
  teams[order(teams$team_id), ]
}

current_glicko <- function(train, as_of) {
  status <- NULL
  for (period in seq(min(month_index(train$end_date)), month_index(as_of))) {
    rows <- month_index(train$end_date) == period
    if (any(rows)) {
      games <- data.frame(
        period = period, a = train$team1_id[rows], b = train$team2_id[rows], score = train$score[rows]
      )
      status <- PlayerRatings::glicko2(games, status = status, gamma = 0, sort = FALSE)$ratings
    } else {
      status <- glicko_empty_month(status)
    }
  }
  status$Deviation <- pmin(350, sqrt(status$Deviation^2 + status$Lag * (status$Volatility * 400 / log(10))^2))
  status
}

current_trueskill <- function(train, as_of, gamma = 0.03) {
  train <- train[order(train$end_date, train$start_date, train$match_id), ]
  p_draw <- (sum(train$score == 0.5) + 1) / (nrow(train) + 2)
  composition <- lapply(seq_len(nrow(train)), function(i) {
    list(as.character(train$team1_id[i]), as.character(train$team2_id[i]))
  })
  results <- lapply(train$score, function(score) c(score, 1 - score))
  history <- TrueSkillThroughTime::History(
    composition, results = results, times = as.numeric(train$end_date),
    mu = 0, sigma = 6, beta = 1, gamma = gamma, p_draw = p_draw
  )
  curves <- history$learning_curves()
  latest <- do.call(rbind, lapply(names(curves), function(id) {
    last <- tail(curves[[id]], 1)[[1]]
    posterior <- TrueSkillThroughTime::forget(last$N, gamma, as.numeric(as_of) - last$t)
    data.frame(team_id = as.integer(id), estimate = posterior@mu, sd = posterior@sigma)
  }))
  list(latest = latest, p_draw = p_draw)
}

current_rating_rows <- function(model, teams, ids, estimate, lower, upper, sd, as_of) {
  if (anyDuplicated(ids) || !setequal(ids, teams$team_id)) stop("Rating team IDs do not match training teams")
  index <- match(teams$team_id, ids)
  rows <- data.frame(
    model = model, as_of = as.Date(as_of), teams, estimate = estimate[index], lower = lower[index],
    upper = upper[index], sd = sd[index]
  )
  if (any(!is.finite(as.matrix(rows[c("estimate", "lower", "upper", "sd")])))) stop("Non-finite current ratings")
  if (any(rows$lower > rows$estimate | rows$upper < rows$estimate | rows$sd < 0)) stop("Invalid rating intervals")
  rows$rank <- NA_integer_
  rows$rank[rows$is_active] <- rank(-rows$estimate[rows$is_active], ties.method = "min")
  rows[order(!rows$is_active, -rows$estimate, rows$team_id), ]
}

read_current_spline <- function(path, train) {
  spline <- readRDS(path)$gam
  grid <- draw_grid(unique(train$format))
  if (!inherits(spline$fit$model, "gam") || !isTRUE(spline$fit$model$converged) ||
        !identical(spline$fit$model$outer.info$conv, "full convergence") ||
        !identical(spline$fit$k, 6L) || !identical(spline$tuning$margin, grid) ||
        any(!is.finite(spline$tuning$log_loss)) ||
        spline$fit$margin != grid[which.min(spline$tuning$log_loss)]) {
    stop("Saved GAM settings or convergence do not match current models")
  }
  inputs <- gam_inputs(train, spline$fit$levels, spline$fit$margin)
  names(inputs)[names(inputs) == "shift"] <- "offset(shift)"
  columns <- c("y", "home", "offset(shift)", "time", "team", "signs")
  if (length(spline$fit$levels$country) > 1L) columns <- c(columns, "country", "country_home")
  if (length(spline$fit$levels$ground) > 1L) columns <- c(columns, "ground", "ground_home")
  observed <- spline$fit$model$model
  if (!setequal(names(observed), columns) ||
        !identical(as.list(observed[columns]), inputs[columns]) ||
        spline$fit$last_date != max(train$start_date)) {
    stop("Saved GAM training inputs do not match the current sample")
  }
  spline
}

run_current_models <- function(format = "Test", iterations = 1000L, gam_fit = NULL) {
  matches <- read_resolved_model_context()
  prepared <- read_prepared("data/build")$manifest
  as_of <- as.Date(prepared$as_of)
  train <- current_training(matches, format, as_of)
  teams <- current_teams(train, as_of)
  reused_spline <- if (!is.null(gam_fit)) read_current_spline(gam_fit, train) else NULL
  output <- file.path("out/analysis/current", tolower(format))
  replace_model_directory(output, function(output) {
    message("Current ", format, " ratings through ", as_of, ": ", nrow(train), " matches")
    readr::write_csv(train[!is.na(train$venue_source), c(
      "match_id", "start_date", "ground_profile_id", "ground_label", "country_original", "country",
      "home_sign_original", "home_sign", "venue_resolution", "venue_source"
    )], file.path(output, "venue_audit.csv"), na = "")
    if (is.null(reused_spline)) {
      spline <- select_spline(train, as_of + 1L)
    } else {
      message("Reusing saved GAM after verifying every training input: ", gam_fit)
      spline <- reused_spline
    }
    readr::write_csv(spline$tuning, file.path(output, "gam_tuning.csv"))
    glicko <- current_glicko(train, as_of)
    trueskill <- current_trueskill(train, as_of)
    saveRDS(list(gam = spline, glicko = glicko, trueskill = trueskill), file.path(output, "fits.rds"))
    stan <- fit_dynamic_skill(train, train[FALSE, ], file.path(output, "stan_draws"),
      iterations = iterations, state_date = as_of
    )
    if (!stan$diagnostics_passed) stop("Stan diagnostics failed; previous current ratings preserved")
    strengths <- export_model_strengths(spline$fit, stan, train, as_of, output, current = TRUE)
    gam <- strengths[strengths$model == "gam" & strengths$date == as_of, ]
    dynamic <- stan$fit$summary(variables = "skill")
    indices <- strcapture("skill\\[([0-9]+),([0-9]+)\\]", dynamic$variable, list(team = integer(), quarter = integer()))
    keep <- indices$quarter == match(quarter_index(as_of), stan$inputs$levels$quarter)
    dynamic_ids <- stan$inputs$levels$team[indices$team[keep]]
    dynamic <- dynamic[keep, ]
    ts <- trueskill$latest
    z <- qnorm(0.95)
    latest <- rbind(
      current_rating_rows("gam", teams, gam$team_id, gam$strength, gam$lower, gam$upper,
        (gam$upper - gam$lower) / (2 * z), as_of
      ),
      current_rating_rows("stan_dynamic_probit", teams, dynamic_ids, dynamic$mean, dynamic$q5, dynamic$q95,
        dynamic$sd, as_of
      ),
      current_rating_rows("glicko2", teams, glicko$Player, glicko$Rating,
        glicko$Rating - z * glicko$Deviation, glicko$Rating + z * glicko$Deviation, glicko$Deviation, as_of
      ),
      current_rating_rows("trueskill", teams, ts$team_id, ts$estimate,
        ts$estimate - z * ts$sd, ts$estimate + z * ts$sd, ts$sd, as_of
      )
    )
    readr::write_csv(latest, file.path(output, "latest.csv"))
    readr::write_csv(data.frame(
      format = format, since = as.Date("2000-01-01"), as_of = as_of,
      rated_matches = nrow(train), teams = nrow(teams), last_result = max(train$end_date),
      unknown_venues = sum(is.na(train$country)),
      resolved_venues = sum(!is.na(train$venue_source))
    ), file.path(output, "coverage.csv"))
    sources <- c(
      list.files("R/models", pattern = "\\.R$", full.names = TRUE), "scripts/models.R",
      "models/dynamic_probit.stan", "renv.lock", "R/pipeline.R",
      "data/context/matches.csv", "data/context/manifest.json",
      "data/context/resolved/matches.csv", "data/context/resolved/manifest.json",
      "data/raw/context/ground_bridge/grounds.csv", "data/raw/context/ground_bridge/manifest.json",
      "data/build/manifest.json", gam_fit
    )
    outputs <- list.files(output, pattern = "\\.(csv|json)$", full.names = TRUE)
    jsonlite::write_json(list(
      format = format, as_of = as_of, since = "2000-01-01", train_ids = train$match_id,
      hashes = setNames(lapply(sources, digest::digest, algo = "sha256", file = TRUE), sources),
      outputs = setNames(lapply(outputs, digest::digest, algo = "sha256", file = TRUE), basename(outputs)),
      stan_diagnostics_passed = stan$diagnostics_passed, chains = 4, iterations_per_chain = iterations,
      gam_fit_reused_from = gam_fit,
      seed = 20261025L, cmdstan_version = as.character(cmdstanr::cmdstan_version()),
      packages = lapply(c("mgcv", "PlayerRatings", "TrueSkillThroughTime", "cmdstanr"), function(name) {
        list(package = name, version = as.character(utils::packageVersion(name)))
      }),
      glicko = list(init = c(2200, 300, 0.15), tau = 1.2, rdmax = 350, period = "calendar month, final month partial"),
      trueskill = list(mu = 0, sigma = 6, beta = 1, gamma = 0.03, time_unit = "day", p_draw = trueskill$p_draw,
        algorithm = "forward filtering; no backward convergence"
      ),
      interpretation = "Current national-team ratings; each model has a separate scale; not forecast evaluation"
    ), file.path(output, "manifest.json"), auto_unbox = TRUE, pretty = TRUE)
    print(latest[c("model", "rank", "team", "estimate", "lower", "upper")])
  })
  invisible(output)
}
