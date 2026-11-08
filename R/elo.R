elo_specification <- function(k = 100, selection = NULL) {
  list(
    model = "elo", implementation = "EloRating::e.single", version = as.character(utils::packageVersion("EloRating")),
    initial_rating = 1000, k = k, k_selection = selection,
    expectation = "normal CDF", rounding = "nearest integer, ties to even",
    ties = "0.5 each, including regulation ties resolved by a tiebreaker",
    no_result = "no update", order = "end_date, start_date, match_id",
    history = "calendar month end; carry forward; no interpolation", active_days = 730, provisional_matches = 10
  )
}

fit_elo <- function(matches, k = 100) {
  if (length(k) != 1L || !is.numeric(k) || is.na(k) || !is.finite(k) || k <= 0) {
    stop("K must be a positive finite number")
  }
  matches <- matches[!is.na(matches$score), ]
  matches <- matches[order(matches$end_date, matches$start_date, matches$match_id), ]
  if (!nrow(matches)) stop("No rated matches")
  if (length(unique(matches$format)) != 1L) stop("Fit each format separately")
  if (any(!matches$score %in% c(0, 0.5, 1))) stop("Invalid score")
  ids <- as.character(unique(c(matches$team1_id, matches$team2_id)))
  values <- setNames(rep(1000, length(ids)), ids)
  updates <- data.frame(
    model = "elo", format = matches$format, match_id = matches$match_id,
    date = matches$end_date, team1_id = matches$team1_id, team2_id = matches$team2_id,
    score = matches$score, team1_before = NA_real_, team2_before = NA_real_,
    team1_after = NA_real_, team2_after = NA_real_
  )
  for (i in seq_len(nrow(matches))) {
    a <- as.character(matches$team1_id[i])
    b <- as.character(matches$team2_id[i])
    updates$team1_before[i] <- values[a]
    updates$team2_before[i] <- values[b]
    pair <- if (matches$score[i] >= 0.5) c(a, b) else c(b, a)
    outcome <- if (matches$score[i] == 0.5) 0 else 1
    values[pair] <- EloRating::e.single(values[pair[1]], values[pair[2]], outcome, k = k, normprob = TRUE)
    updates$team1_after[i] <- values[a]
    updates$team2_after[i] <- values[b]
  }
  if (any(updates$team1_before + updates$team2_before != updates$team1_after + updates$team2_after)) {
    stop("Rating update failed conservation check")
  }
  list(matches = matches, updates = updates)
}

elo_snapshot <- function(model, date) {
  matches <- model$matches[model$matches$end_date <= date, ]
  if (!nrow(matches)) {
    return(NULL)
  }
  updates <- model$updates[model$updates$date <= date, ]
  appearances <- rbind(
    data.frame(
      team_id = matches$team1_id, team = matches$team1, rating = updates$team1_after,
      date = matches$end_date, sequence = seq_len(nrow(matches))
    ),
    data.frame(
      team_id = matches$team2_id, team = matches$team2, rating = updates$team2_after,
      date = matches$end_date, sequence = seq_len(nrow(matches))
    )
  )
  appearances <- appearances[order(appearances$sequence), ]
  last <- appearances[!duplicated(appearances$team_id, fromLast = TRUE), ]
  counts <- table(appearances$team_id)
  result <- data.frame(
    model = "elo", format = matches$format[1], date = date, team_id = last$team_id,
    team = last$team, rating = last$rating,
    rated_matches = as.integer(counts[as.character(last$team_id)]), last_rated_match = last$date
  )
  if (anyNA(result$rating)) stop("Missing rating for a team with completed matches")
  result$is_active <- as.integer(date - result$last_rated_match) <= 730L
  result$is_provisional <- result$rated_matches < 10L
  result$rank <- NA_integer_
  result$rank[result$is_active] <- rank(-result$rating[result$is_active], ties.method = "min")
  result <- result[order(!result$is_active, -result$rating, result$team_id), ]
  rownames(result) <- NULL
  result
}

calculate_elo <- function(matches, as_of, k = 100, selection = NULL) {
  matches <- matches[matches$end_date <= as_of, ]
  pools <- split(matches, matches$format)
  if (length(k) == 1L && is.null(names(k))) k <- setNames(rep(k, length(pools)), names(pools))
  if (!is.numeric(k) || anyDuplicated(names(k)) || !setequal(names(k), names(pools))) {
    stop("K must be a scalar or a named value for each format")
  }
  models <- lapply(names(pools), function(format) fit_elo(pools[[format]], k[[format]]))
  names(models) <- names(pools)
  latest <- do.call(rbind, lapply(models, elo_snapshot, date = as_of))
  monthly <- lapply(models, function(model) {
    first <- as.Date(format(min(model$matches$end_date), "%Y-%m-01"))
    last <- as.Date(format(as_of, "%Y-%m-01"))
    ends <- seq(first, seq(last, by = "month", length.out = 2)[2], by = "month")[-1] - 1
    ends <- ends[ends <= as_of]
    if (!length(ends)) {
      return(latest[FALSE, ])
    }
    do.call(rbind, lapply(as.list(ends), function(date) elo_snapshot(model, date)))
  })
  monthly <- do.call(rbind, monthly)
  updates <- do.call(rbind, lapply(models, `[[`, "updates"))
  latest$k <- unname(k[latest$format])
  monthly$k <- unname(k[monthly$format])
  updates$k <- unname(k[updates$format])
  list(
    latest = latest, monthly = monthly, updates = updates, models = models,
    specification = elo_specification(as.list(k), selection)
  )
}
