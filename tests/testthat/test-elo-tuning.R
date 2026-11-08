tuning_matches <- function() {
  years <- rep(2005:2020, each = 12L)
  dates <- as.Date(paste0(years, "-01-01")) + rep(seq(5L, 335L, by = 30L), 16L)
  data.frame(
    match_id = seq_along(dates), format = "ODI", start_date = dates, end_date = dates,
    team1_id = 1L, team2_id = 2L, team1 = "A", team2 = "B",
    result = "win", score = rep(c(1, 1, 0, 1, 0, 0.5), length.out = length(dates))
  )
}

tuning_specification <- function() {
  specification <- elo_tuning_specification()
  specification$k_grid <- c(1, 16, 32, 100)
  specification$first_evaluation_year <- 2015L
  specification$minimum_matches <- 20L
  specification
}

testthat::test_that("K is configurable and updates match the official scalar reference", {
  matches <- tuning_matches()[1:3, ]
  matches$score <- c(1, 0.5, 0)
  for (k in c(1, 16, 31, 32, 100, 200, 400)) {
    model <- fit_elo(matches, k)
    reference <- c(1000, 1000)
    for (i in seq_len(nrow(matches))) {
      outcome <- c(2, 0, 1)[match(matches$score[i], c(0, 0.5, 1))]
      reference <- EloRating::e.single(reference[1], reference[2], outcome, k = k)
      testthat::expect_equal(unname(unlist(model$updates[i, c("team1_after", "team2_after")])), reference)
    }
  }
  testthat::expect_equal(fit_elo(matches)$updates, fit_elo(matches, 100)$updates)
  testthat::expect_equal(fit_elo(matches, 32)$updates$team1_after[1], 1016)
  testthat::expect_true(all(fit_elo(matches, 1)$updates$team1_after == 1000))
  for (invalid in list(0, -1, NA_real_, Inf, c(16, 32), "32")) {
    testthat::expect_error(fit_elo(matches, invalid), "K must")
  }
})

testthat::test_that("pre-match forecasts exclude same-day and overlapping completions", {
  matches <- tuning_matches()[1:4, ]
  matches$format <- "Test"
  matches$start_date <- as.Date(c("2020-01-01", "2020-01-03", "2020-01-05", "2020-01-07"))
  matches$end_date <- as.Date(c("2020-01-05", "2020-01-04", "2020-01-06", "2020-01-08"))
  matches$score <- 1
  model <- fit_elo(matches)
  predictions <- setNames(elo_pre_match_predictions(model), model$matches$match_id)
  testthat::expect_equal(unname(predictions[c("1", "2")]), c(0.5, 0.5))
  testthat::expect_equal(unname(predictions["3"]), pnorm(100 / (200 * sqrt(2))))
  for (i in seq_len(nrow(matches))) {
    past <- matches[matches$end_date < matches$start_date[i], ]
    expected <- if (!nrow(past)) {
      0.5
    } else {
      last <- tail(fit_elo(past)$updates, 1)
      pnorm((last$team1_after - last$team2_after) / (200 * sqrt(2)))
    }
    testthat::expect_equal(unname(predictions[as.character(matches$match_id[i])]), expected)
  }
  changed <- matches
  changed$score[1] <- 0
  revised <- fit_elo(changed)
  revised_p <- setNames(elo_pre_match_predictions(revised), revised$matches$match_id)
  testthat::expect_equal(revised_p[c("1", "2", "3")], predictions[c("1", "2", "3")])
  testthat::expect_false(isTRUE(all.equal(revised_p["4"], predictions["4"])))
})

testthat::test_that("no-results, input order and team labels do not alter candidate forecasts", {
  matches <- tuning_matches()[1:20, ]
  matches$score[5] <- NA_real_
  cutoff <- max(matches$end_date)
  grid <- c(16, 100)
  original <- replay_elo_grid(matches, grid, cutoff)
  without <- replay_elo_grid(matches[!is.na(matches$score), ], grid, cutoff)
  reversed <- replay_elo_grid(matches[rev(seq_len(nrow(matches))), ], grid, cutoff)
  testthat::expect_equal(original, without)
  testthat::expect_equal(original, reversed)
  swapped <- matches
  swapped$team1_id <- matches$team2_id
  swapped$team2_id <- matches$team1_id
  swapped$team1 <- matches$team2
  swapped$team2 <- matches$team1
  swapped$score <- 1 - matches$score
  other <- replay_elo_grid(swapped, grid, cutoff)
  testthat::expect_equal(unname(other$predictions), unname(1 - original$predictions))
  testthat::expect_error(replay_elo_grid(matches, c(16, 16, 100), cutoff), "Invalid K grid")
  testthat::expect_error(replay_elo_grid(matches, 16, cutoff), "fixed baseline")
  matches$end_date[1] <- matches$start_date[1] - 1L
  testthat::expect_error(replay_elo_grid(matches, grid, cutoff), "chronology")
})

testthat::test_that("forecasts use each team's own last rating and neutral debut ratings", {
  matches <- tuning_matches()[1:4, ]
  matches$team1_id <- c(1L, 3L, 2L, 3L)
  matches$team2_id <- c(2L, 1L, 3L, 4L)
  matches$team1 <- c("A", "C", "B", "C")
  matches$team2 <- c("B", "A", "C", "D")
  matches$score <- c(1, 0, 1, 1)
  model <- fit_elo(matches)
  forecasts <- elo_pre_match_predictions(model)
  testthat::expect_equal(forecasts[1], 0.5)
  testthat::expect_equal(forecasts[2], pnorm((1000 - 1050) / (200 * sqrt(2))))
  testthat::expect_equal(
    forecasts[3],
    pnorm((model$updates$team2_after[1] - model$updates$team1_after[2]) / (200 * sqrt(2)))
  )
  testthat::expect_equal(forecasts[4], pnorm((model$updates$team2_after[3] - 1000) / (200 * sqrt(2))))
})

testthat::test_that("future results cannot change earlier selections or forecasts", {
  matches <- tuning_matches()
  specification <- tuning_specification()
  cutoff <- as.Date("2020-12-31")
  original <- replay_elo_grid(matches, specification$k_grid, cutoff)
  result <- evaluate_elo_tuning(original, cutoff, specification)
  changed <- matches
  changed$score[changed$start_date >= as.Date("2019-01-01")] <- 1
  revised <- replay_elo_grid(changed, specification$k_grid, cutoff)
  other <- evaluate_elo_tuning(revised, cutoff, specification)
  testthat::expect_equal(result$tuning[result$tuning$year <= 2019, ], other$tuning[other$tuning$year <= 2019, ])
  testthat::expect_equal(
    result$evaluation[result$evaluation$year < 2019, ],
    other$evaluation[other$evaluation$year < 2019, ]
  )
  truncated <- replay_elo_grid(matches, specification$k_grid, as.Date("2018-12-31"))
  testthat::expect_equal(
    original$predictions[original$matches$end_date <= as.Date("2018-12-31"), ],
    truncated$predictions
  )
  testthat::expect_false(isTRUE(all.equal(
    result$tuning[result$tuning$year == 2020, ],
    other$tuning[other$tuning$year == 2020, ]
  )))
})

testthat::test_that("New-Year matches use their starting-year K and cannot enter January tuning", {
  matches <- tuning_matches()
  extra <- matches[1, ]
  extra$match_id <- 999L
  extra$start_date <- as.Date("2018-12-30")
  extra$end_date <- as.Date("2019-01-03")
  matches <- rbind(matches, extra)
  specification <- tuning_specification()
  cutoff <- as.Date("2020-12-31")
  replay <- replay_elo_grid(matches, specification$k_grid, cutoff)
  result <- evaluate_elo_tuning(replay, cutoff, specification)
  forecast <- result$evaluation[result$evaluation$match_id == 999 & result$evaluation$window == 5, ]
  fold <- result$folds[result$folds$year == 2018 & result$folds$window == 5, ]
  testthat::expect_equal(nrow(forecast), 1L)
  testthat::expect_equal(forecast$year, 2018L)
  testthat::expect_equal(forecast$selected_k, fold$selected_k)
  without <- replay_elo_grid(matches[matches$match_id != 999, ], specification$k_grid, cutoff)
  with_choice <- select_elo_k(replay, as.Date("2019-01-01"), 5, specification$minimum_matches)
  without_choice <- select_elo_k(without, as.Date("2019-01-01"), 5, specification$minimum_matches)
  testthat::expect_true(with_choice$supported)
  testthat::expect_equal(with_choice, without_choice)
})

testthat::test_that("reported scores can be reconstructed from forecasts including draws", {
  matches <- tuning_matches()
  specification <- tuning_specification()
  cutoff <- as.Date("2020-10-25")
  replay <- replay_elo_grid(matches, specification$k_grid, cutoff)
  result <- evaluate_elo_tuning(replay, cutoff, specification)
  for (i in seq_len(nrow(result$folds))) {
    fold <- result$folds[i, ]
    choice <- select_elo_k(replay, fold$origin, fold$window, specification$minimum_matches)
    testthat::expect_equal(fold$selected_k, choice$k)
    rows <- result$evaluation[result$evaluation$window == fold$window & result$evaluation$year == fold$year, ]
    testthat::expect_equal(fold$tuned_mse, mean((rows$score - rows$expected_score)^2))
    for (j in seq_len(nrow(rows))) {
      p <- replay$predictions[
        match(rows$match_id[j], replay$matches$match_id),
        match(rows$selected_k[j], replay$k_grid)
      ]
      testthat::expect_equal(rows$expected_score[j], unname(p))
    }
  }
  primary <- result$evaluation[result$evaluation$window == 5, ]
  summary <- result$summary[result$summary$scope == "available" & result$summary$window == 5, ]
  testthat::expect_equal(summary$tuned_mse, mean(primary$squared_error))
  testthat::expect_equal(summary$n, nrow(primary))
  testthat::expect_true(any(primary$score == 0.5))
  testthat::expect_true(result$current_selection$partial_year)
  testthat::expect_equal(
    result$current_selection$selected_k,
    select_elo_k(replay, as.Date("2020-01-01"), 5, specification$minimum_matches)$k
  )
  n_teams <- length(unique(c(matches$team1_id, matches$team2_id)))
  testthat::expect_equal(sum(result$ratings$is_selected), n_teams)
})

testthat::test_that("unsupported tuning windows stay explicit and exact ties prefer smaller K", {
  matches <- tuning_matches()
  matches <- matches[matches$start_date >= as.Date("2008-01-01"), ]
  specification <- tuning_specification()
  cutoff <- as.Date("2020-12-31")
  replay <- replay_elo_grid(matches, specification$k_grid, cutoff)
  result <- evaluate_elo_tuning(replay, cutoff, specification)
  testthat::expect_false(result$folds$supported[result$folds$year == 2015 & result$folds$window == 10])
  common <- result$summary[result$summary$scope == "common", ]
  testthat::expect_length(unique(common$n), 1L)
  testthat::expect_equal(unique(common$first_year), 2018L)
  replay$predictions[, ] <- 0.5
  testthat::expect_equal(select_elo_k(replay, as.Date("2020-01-01"), 5, 20)$k, 1)
})

testthat::test_that("saved-output verification detects corrupted files and incorrect exported metrics", {
  specification <- tuning_specification()
  cutoff <- as.Date("2020-12-31")
  replay <- replay_elo_grid(tuning_matches(), specification$k_grid, cutoff)
  result <- evaluate_elo_tuning(replay, cutoff, specification)
  directory <- withr::local_tempdir()
  for (name in names(result)) readr::write_csv(result[[name]], file.path(directory, paste0(name, ".csv")))
  forecasts <- do.call(rbind, lapply(seq_along(replay$k_grid), function(j) {
    data.frame(k = replay$k_grid[j], replay$matches, expected_score = replay$predictions[, j])
  }))
  readr::write_csv(forecasts, file.path(directory, "candidate_predictions.csv.gz"))
  manifest_path <- file.path(directory, "manifest.json")
  write_manifest <- function() {
    files <- setdiff(list.files(directory, full.names = TRUE), manifest_path)
    write_json(
      list(
        format = "ODI", specification = specification,
        files = as.list(setNames(vapply(files, sha256, character(1)), basename(files)))
      ),
      manifest_path
    )
  }
  write_manifest()
  testthat::expect_true(suppressMessages(check_elo_tuning(directory)))
  summary_path <- file.path(directory, "summary.csv")
  summary <- readr::read_csv(summary_path, show_col_types = FALSE)
  summary$tuned_mse[1] <- summary$tuned_mse[1] + 0.01
  readr::write_csv(summary, summary_path)
  testthat::expect_error(check_elo_tuning(directory), "checksum mismatch")
  write_manifest()
  testthat::expect_error(check_elo_tuning(directory), "disagree with reconstructed")
  readr::write_csv(result$summary, summary_path)
  evaluation_path <- file.path(directory, "evaluation.csv")
  readr::write_csv(rbind(result$evaluation, result$evaluation[1, ]), evaluation_path)
  write_manifest()
  testthat::expect_error(check_elo_tuning(directory), "Duplicate evaluation")
  readr::write_csv(result$evaluation[-1, ], evaluation_path)
  write_manifest()
  testthat::expect_error(check_elo_tuning(directory), "Incomplete evaluation fold")
  readr::write_csv(result$evaluation, evaluation_path)
  readr::write_csv(forecasts[-1, ], file.path(directory, "candidate_predictions.csv.gz"))
  write_manifest()
  testthat::expect_error(check_elo_tuning(directory), "Incomplete candidate grid")
})

testthat::test_that("production K selection matches the annual policy without using current-year outcomes", {
  matches <- tuning_matches()
  specification <- tuning_specification()
  cutoff <- as.Date("2020-12-31")
  selected <- select_production_elo_k(matches, cutoff, specification)
  evaluated <- evaluate_elo_tuning(replay_elo_grid(matches, specification$k_grid, cutoff), cutoff, specification)
  testthat::expect_equal(unname(selected$k), evaluated$current_selection$selected_k)
  testthat::expect_equal(selected$selections$n_tuning, evaluated$current_selection$n_tuning)
  matches$score[matches$start_date >= as.Date("2020-01-01")] <- 1
  testthat::expect_equal(select_production_elo_k(matches, cutoff, specification), selected)
  testthat::expect_error(select_production_elo_k(matches, as.Date("2006-01-01"), specification), "Insufficient")
})

testthat::test_that("calculation applies distinct K values and records them throughout outputs", {
  matches <- tuning_matches()[1:4, ]
  second <- matches
  second$format <- "Test"
  second$match_id <- second$match_id + 1000L
  result <- calculate_elo(rbind(matches, second), max(matches$end_date), k = c(ODI = 16, Test = 32))
  for (table in c("latest", "monthly", "updates")) {
    rows <- result[[table]]
    testthat::expect_equal(unique(rows$k[rows$format == "ODI"]), 16)
    testthat::expect_equal(unique(rows$k[rows$format == "Test"]), 32)
  }
  testthat::expect_equal(result$updates$team1_after[result$updates$format == "ODI"][1], 1008)
  testthat::expect_equal(result$updates$team1_after[result$updates$format == "Test"][1], 1016)
  testthat::expect_equal(result$specification$k, list(ODI = 16, Test = 32))
  testthat::expect_error(calculate_elo(rbind(matches, second), max(matches$end_date), k = c(ODI = 16)), "each format")
})


testthat::test_that("default analysis selects K and publishes its auditable selection inputs", {
  withr::local_dir(root)
  directory <- withr::local_tempdir()
  prepared <- file.path(directory, "build")
  analysis <- file.path(directory, "analysis")
  dir.create(prepared)
  matches <- tuning_matches()
  second <- matches
  second$match_id <- second$match_id + nrow(matches)
  second$start_date <- second$start_date + 1L
  second$end_date <- second$end_date + 1L
  matches <- rbind(matches, second)
  matches$source_url <- "fixture"
  path <- file.path(prepared, "matches.csv")
  readr::write_csv(matches, path)
  write_json(list(as_of = "2020-12-31", matches_sha256 = sha256(path)), file.path(prepared, "manifest.json"))
  analyze_data(prepared, analysis)
  published <- read_analysis(analysis)
  selection <- readr::read_csv(file.path(analysis, "k_selection.csv"), show_col_types = FALSE)
  curves <- readr::read_csv(file.path(analysis, "k_tuning.csv"), show_col_types = FALSE)
  testthat::expect_equal(published$manifest$specification$k$ODI, selection$k)
  testthat::expect_equal(unique(published$latest$k), selection$k)
  testthat::expect_equal(selection$k, curves$k[which.min(curves$mse)])
  testthat::expect_equal(selection$origin, as.Date("2020-01-01"))
  testthat::expect_true(all(c("k_selection.csv", "k_tuning.csv") %in% names(published$manifest$files)))
  testthat::expect_equal(published$manifest$specification$k_selection$window_years, 5)
  analyze_data(prepared, analysis, k = 100)
  testthat::expect_equal(unique(read_analysis(analysis)$latest$k), 100)
  testthat::expect_false(file.exists(file.path(analysis, "k_selection.csv")))
})
