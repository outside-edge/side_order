latest_team_labels <- function(matches) {
  matches <- matches[order(matches$end_date, matches$start_date, matches$match_id), ]
  appearances <- rbind(
    data.frame(team_id = matches$team1_id, team = matches$team1, sequence = seq_len(nrow(matches))),
    data.frame(team_id = matches$team2_id, team = matches$team2, sequence = seq_len(nrow(matches)))
  )
  appearances <- appearances[order(appearances$sequence), ]
  teams <- appearances[!duplicated(appearances$team_id, fromLast = TRUE), c("team_id", "team")]
  teams <- teams[order(teams$team_id), ]
  rownames(teams) <- NULL
  teams
}

outcome_category <- function(score) {
  if (any(!is.na(score) & !score %in% c(0, 0.5, 1))) stop("Invalid match score")
  match(score, c(0, 0.5, 1))
}

forecast_split <- function(matches, origin, until, format = "Test", since = as.Date("2000-01-01")) {
  origin <- as.Date(origin)
  until <- as.Date(until)
  if (origin >= until || since >= origin) stop("Invalid forecast window")
  invitational <- c("ICC World XI", "World-XI", "Asia XI", "Africa XI")
  eligible <- matches[
    matches$format == format & matches$start_date >= since & !is.na(matches$score) &
      !matches$team1 %in% invitational & !matches$team2 %in% invitational,
  ]
  known <- !is.na(eligible$country)
  train <- eligible[known & eligible$end_date < origin, ]
  test <- eligible[known & eligible$start_date >= origin & eligible$start_date < until, ]
  if (nrow(train) < 50L || !nrow(test)) stop("Insufficient train/test data")
  list(
    train = train, test = test,
    coverage = data.frame(
      split = c("training", "evaluation"),
      total = c(sum(eligible$end_date < origin), sum(eligible$start_date >= origin & eligible$start_date < until)),
      known_country = c(nrow(train), nrow(test))
    )
  )
}

check_probabilities <- function(p) {
  if (!is.matrix(p) || ncol(p) != 3L) stop("Invalid outcome probabilities")
  invalid <- anyNA(p) || any(!is.finite(p)) || any(p < 0 | p > 1) || any(abs(rowSums(p) - 1) > 1e-8)
  if (invalid) stop("Invalid outcome probabilities")
  invisible(p)
}

probability_metrics <- function(p, score) {
  check_probabilities(p)
  y <- outcome_category(score)
  if (length(y) != nrow(p) || anyNA(y)) stop("Missing or mismatched evaluation outcomes")
  observed <- diag(3)[y, , drop = FALSE]
  maxima <- abs(p - apply(p, 1, max)) < 1e-12
  data.frame(
    n = length(y), log_loss = -mean(log(p[cbind(seq_along(y), y)])),
    brier = mean(rowSums((p - observed)^2)), accuracy = mean(rowSums(maxima * observed) / rowSums(maxima))
  )
}

replace_model_directory <- function(output, write) {
  replace_directory(output, function(staging) {
    tryCatch(write(staging), error = function(error) {
      failed <- tempfile("failed-", tmpdir = dirname(output))
      if (!file.rename(staging, failed)) stop("Cannot retain failed model run: ", staging)
      message("Failed model run retained in ", failed)
      stop(error)
    })
  })
}

month_index <- function(date) as.integer(format(date, "%Y")) * 12L + as.integer(format(date, "%m")) - 1L
month_date <- function(index) as.Date(sprintf("%04d-%02d-01", index %/% 12L, index %% 12L + 1L))
quarter_index <- function(date) as.integer(format(date, "%Y")) * 4L + (as.integer(format(date, "%m")) - 1L) %/% 3L

previous_year <- function(date) {
  day <- format(date, "%m-%d")
  day[day == "02-29"] <- "02-28"
  as.Date(sprintf("%d-%s", as.integer(format(date, "%Y")) - 1L, day))
}

swap_teams <- function(matches) {
  result <- matches
  result$team1 <- matches$team2
  result$team2 <- matches$team1
  result$team1_id <- matches$team2_id
  result$team2_id <- matches$team1_id
  result$home_sign <- -matches$home_sign
  result$score <- 1 - matches$score
  result
}

draw_grid <- function(format) {
  if (format == "Test") c(0.2, 0.5, 1, 1.5) else c(0.005, 0.02, 0.05, 0.1)
}

calibration_table <- function(p, score, bins = 5L) {
  y <- outcome_category(score)
  do.call(rbind, lapply(seq_len(3), function(j) {
    groups <- pmin(bins, floor(p[, j] * bins) + 1L)
    do.call(rbind, lapply(sort(unique(groups)), function(bin) {
      rows <- groups == bin
      data.frame(
        outcome = c("loss", "draw_tie", "win")[j], bin = bin, n = sum(rows),
        predicted = mean(p[rows, j]), observed = mean(y[rows] == j)
      )
    }))
  }))
}
