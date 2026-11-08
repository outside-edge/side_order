test_that("current fits include completed cutoff-day games without requiring a future sample", {
  matches <- simulated_matches(100L)
  cutoff <- max(matches$end_date) - 10L
  matches$start_date[1:4] <- cutoff - 4L
  matches$end_date[1:4] <- cutoff + c(0L, 1L, 0L, 0L)
  matches$score[3] <- NA_real_
  matches$team1[4] <- "ICC World XI"
  selected <- current_training(matches, "Test", cutoff)
  expect_true(1L %in% selected$match_id)
  expect_false(any(c(2L, 3L, 4L) %in% selected$match_id))
  expect_true(all(selected$end_date <= cutoff))
  altered <- matches
  altered$score[altered$end_date > cutoff] <- 1 - altered$score[altered$end_date > cutoff]
  expect_equal(current_training(altered, "Test", cutoff), selected)
  matches$country[1] <- NA_character_
  expect_error(current_training(matches, "Test", cutoff), "complete venue coverage")
})

test_that("TrueSkill agrees with a direct package update and handles ties and inactivity", {
  matches <- simulated_matches(1L)
  matches$team1_id <- 1L
  matches$team2_id <- 2L
  matches$score <- 1
  cutoff <- matches$end_date
  fitted <- current_trueskill(matches, cutoff)
  game <- TrueSkillThroughTime::Game(
    list(c(TrueSkillThroughTime::Player()), c(TrueSkillThroughTime::Player())),
    result = c(1, 0), p_draw = fitted$p_draw
  )
  expected <- TrueSkillThroughTime::posteriors(game)
  rows <- fitted$latest[match(1:2, fitted$latest$team_id), ]
  expect_equal(rows$estimate, vapply(expected, function(x) x[[1]]@mu, numeric(1)))
  expect_equal(rows$sd, vapply(expected, function(x) x[[1]]@sigma, numeric(1)))
  later <- current_trueskill(matches, cutoff + 100L)$latest
  later <- later[match(rows$team_id, later$team_id), ]
  expect_equal(later$estimate, rows$estimate)
  expect_equal(later$sd^2, rows$sd^2 + 100 * 0.03^2)
  reversed <- current_trueskill(swap_teams(matches), cutoff)$latest
  expect_equal(reversed[match(rows$team_id, reversed$team_id), ], rows, ignore_attr = TRUE)
  matches$score <- 0.5
  tied <- current_trueskill(matches, cutoff)$latest
  expect_equal(tied$estimate, c(0, 0), tolerance = 1e-10)
})

test_that("current Glicko includes a partial final month and inflates empty months", {
  matches <- simulated_matches(100L)
  matches$start_date <- as.Date("2020-01-01")
  matches$end_date <- as.Date("2020-01-05")
  cutoff <- as.Date("2020-01-20")
  fit <- current_glicko(matches, cutoff)
  expected <- PlayerRatings::glicko2(data.frame(
    period = 1, a = matches$team1_id, b = matches$team2_id, score = matches$score
  ), gamma = 0, sort = FALSE)$ratings
  expect_equal(fit, expected)
  later <- current_glicko(matches, as.Date("2020-03-20"))
  expect_equal(later$Rating, fit$Rating)
  expect_equal(later$Deviation, pmin(350, sqrt(fit$Deviation^2 + 2 * (fit$Volatility * 400 / log(10))^2)))
  expect_equal(current_glicko(matches, cutoff), fit)
})

test_that("current rows align by ID and rank only active teams", {
  train <- simulated_matches(100L)
  cutoff <- max(train$end_date)
  teams <- current_teams(train, cutoff)
  teams$is_active[1] <- FALSE
  ids <- rev(teams$team_id)
  rows <- current_rating_rows("test", teams, ids, ids, ids - 1, ids + 1, rep(1, 4), cutoff)
  expect_equal(rows$estimate, as.numeric(rows$team_id))
  expect_true(is.na(rows$rank[rows$team_id == teams$team_id[1]]))
  expect_equal(sort(na.omit(rows$rank)), 1:3, ignore_attr = TRUE)
  expect_error(current_rating_rows("test", teams, rep(1, 4), ids, ids - 1, ids + 1, rep(1, 4), cutoff), "IDs")
})

test_that("Stan current data need no held-out outcomes and extend through empty quarters", {
  train <- simulated_matches(100L)
  cutoff <- max(train$end_date) + 400L
  inputs <- stan_inputs(train, train[FALSE, ], state_date = cutoff)
  expect_equal(inputs$data$N, inputs$data$N_train)
  expect_equal(max(inputs$levels$quarter), quarter_index(cutoff))
  expect_length(inputs$data$y, nrow(train))
})

test_that("explicit venue mappings retain their source and resolve new grounds", {
  matches <- simulated_matches(1L)
  matches$team1 <- "India"
  matches$team2 <- "Afghanistan"
  profiles <- data.frame(match_id = 1L, ground_profile_id = 1290799L, ground_label = "New Chandigarh")
  legacy <- data.frame(match_id = integer(), team1 = character(), team2 = character(), ground = character())
  grounds <- data.frame(ground = character(), country = character())
  periods <- data.frame(ground_profile_id = 1290799L, country = "India",
    valid_from = as.Date("2000-01-01"), valid_until = as.Date("9999-12-31")
  )
  joined <- join_match_context(matches, profiles, legacy, grounds, periods)$matches
  expect_equal(joined$home_sign, 1L)
  expect_equal(joined$context_source, "audited ground jurisdiction periods")
})

test_that("Glicko inactivity grows once when other teams continue playing", {
  matches <- simulated_matches(4L)
  matches$team1_id <- c(1L, 1L, 1L, 1L)
  matches$team2_id <- c(2L, 3L, 2L, 2L)
  matches$start_date <- as.Date(c("2020-01-01", "2020-01-10", "2020-02-01", "2020-03-01"))
  matches$end_date <- matches$start_date + 4L
  january <- current_glicko(matches[1:2, ], as.Date("2020-01-31"))
  march <- current_glicko(matches, as.Date("2020-03-31"))
  before <- january[january$Player == 3, ]
  after <- march[march$Player == 3, ]
  expect_equal(after$Lag, 2)
  expect_equal(after$Rating, before$Rating)
  expect_equal(after$Deviation, pmin(350, sqrt(before$Deviation^2 + 2 * (before$Volatility * 400 / log(10))^2)))
})

test_that("TrueSkill history matches sequential package updates on different days", {
  matches <- simulated_matches(2L)
  matches$team1_id <- c(1L, 2L)
  matches$team2_id <- c(2L, 1L)
  matches$score <- c(1, 0.5)
  matches$end_date <- as.Date("2020-01-01") + c(0, 10)
  fitted <- current_trueskill(matches, max(matches$end_date))
  first <- TrueSkillThroughTime::Game(
    list(c(TrueSkillThroughTime::Player()), c(TrueSkillThroughTime::Player())),
    result = c(1, 0), p_draw = fitted$p_draw
  )
  initial <- TrueSkillThroughTime::posteriors(first)
  priors <- lapply(initial, function(x) {
    c(TrueSkillThroughTime::Player(TrueSkillThroughTime::forget(x[[1]], 0.03, 10)))
  })
  second <- TrueSkillThroughTime::Game(rev(priors), result = c(0.5, 0.5), p_draw = fitted$p_draw)
  expected <- rev(TrueSkillThroughTime::posteriors(second))
  rows <- fitted$latest[match(1:2, fitted$latest$team_id), ]
  expect_equal(rows$estimate, vapply(expected, function(x) x[[1]]@mu, numeric(1)), tolerance = 1e-6)
  expect_equal(rows$sd, vapply(expected, function(x) x[[1]]@sigma, numeric(1)), tolerance = 1e-6)
})

test_that("inner validation dates handle leap-day cutoffs", {
  expect_equal(previous_year(as.Date("2024-02-29")), as.Date("2023-02-28"))
  expect_equal(previous_year(as.Date("2025-03-01")), as.Date("2024-03-01"))
})

test_that("renamed teams keep one identity and their latest observed label", {
  train <- simulated_matches(3L)
  train$team1_id <- c(1L, 2L, 1L)
  train$team2_id <- c(2L, 1L, 2L)
  train$team1 <- c("Swaziland", "India", "Eswatini")
  train$team2 <- c("India", "Swaziland", "India")
  teams <- current_teams(train[c(3, 1, 2), ], max(train$end_date))
  expect_equal(teams$team_id, 1:2)
  expect_equal(teams$team, c("Eswatini", "India"))
  expect_equal(teams$rated_matches, c(3L, 3L))
  expect_equal(latest_team_labels(swap_teams(train)), latest_team_labels(train))
  expect_equal(latest_team_labels(train[1:2, ])$team[1], "Swaziland")
  expect_equal(normalize_jurisdiction(c("Swaziland", "Eswatini")), rep("Eswatini", 2))
})

test_that("saved GAM reuse rejects changed training data and settings", {
  train <- simulated_matches(100L)
  grid <- draw_grid("Test")
  spline <- list(fit = fit_spline(train, grid[1]), tuning = data.frame(margin = grid, log_loss = 1:4))
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path))
  saveRDS(list(gam = spline), path)
  reused <- read_current_spline(path, train)
  expect_equal(coef(reused$fit$model), coef(spline$fit$model))
  changed <- train
  changed$score[1] <- if (changed$score[1] == 1) 0 else 1
  expect_error(read_current_spline(path, changed), "training inputs")
  changed <- train
  changed$home_sign[1] <- 1 - changed$home_sign[1]
  expect_error(read_current_spline(path, changed), "training inputs")
  changed <- train
  changed$start_date[1] <- changed$start_date[1] + 1L
  expect_error(read_current_spline(path, changed), "training inputs")
  expect_error(read_current_spline(path, train[-1, ]), "training inputs")
  spline$fit$k <- 5L
  saveRDS(list(gam = spline), path)
  expect_error(read_current_spline(path, train), "settings")
})
