elo_tuning_specification <- function() {
  list(
    k_grid = c(seq_len(200), seq(220, 400, by = 20)),
    first_evaluation_year = 2015L, windows = c(3L, 5L, 10L), primary_window = 5L,
    minimum_matches = 100L, near_minimum_mse = 0.001,
    objective = "match-weighted squared error of expected score; draws/ties = 0.5",
    selection = "previous complete calendar years; smaller K breaks exact ties",
    prediction = "results completed strictly before match start date",
    interpretation = "retrospective nested chronological evaluation; not blinded confirmation"
  )
}

elo_pre_match_predictions <- function(model) {
  matches <- model$matches
  updates <- model$updates
  ratings <- matrix(1000, nrow = nrow(matches), ncol = 2L)
  for (team in unique(c(matches$team1_id, matches$team2_id))) {
    history <- updates[updates$team1_id == team | updates$team2_id == team, ]
    after <- ifelse(history$team1_id == team, history$team1_after, history$team2_after)
    for (side in 1:2) {
      rows <- which(matches[[paste0("team", side, "_id")]] == team)
      index <- findInterval(as.numeric(matches$start_date[rows]) - 1, as.numeric(history$date))
      ratings[rows, side] <- c(1000, after)[index + 1L]
    }
  }
  stats::pnorm((ratings[, 1] - ratings[, 2]) / (200 * sqrt(2)))
}

replay_elo_grid <- function(matches, k_grid, as_of, progress = FALSE) {
  if (!inherits(as_of, "Date") || length(as_of) != 1L || is.na(as_of)) stop("Invalid tuning cutoff")
  if (!length(k_grid) || anyNA(k_grid) || any(!is.finite(k_grid) | k_grid <= 0) || anyDuplicated(k_grid)) {
    stop("Invalid K grid")
  }
  if (!100 %in% k_grid) stop("K grid must contain the fixed baseline, 100")
  k_grid <- sort(k_grid)
  required <- c("match_id", "format", "start_date", "end_date", "team1_id", "team2_id", "team1", "team2")
  if (!all(c(required, "score") %in% names(matches)) || anyNA(matches[required])) stop("Invalid match fields")
  if (!inherits(matches$start_date, "Date") || !inherits(matches$end_date, "Date")) stop("Dates must be Date values")
  if (anyDuplicated(matches$match_id) || any(matches$end_date < matches$start_date)) stop("Invalid match chronology")
  if (any(matches$team1_id == matches$team2_id)) stop("A team cannot play itself")
  matches <- matches[matches$end_date <= as_of & !is.na(matches$score), ]
  if (length(unique(matches$format)) != 1L) stop("Replay one nonempty format at a time")
  matches <- matches[order(matches$end_date, matches$start_date, matches$match_id), ]
  rownames(matches) <- NULL
  predictions <- matrix(NA_real_, nrow(matches), length(k_grid), dimnames = list(matches$match_id, k_grid))
  ratings <- vector("list", length(k_grid))
  baseline <- NULL
  for (j in seq_along(k_grid)) {
    model <- fit_elo(matches, k = k_grid[j])
    predictions[, j] <- elo_pre_match_predictions(model)
    ratings[[j]] <- cbind(k = k_grid[j], elo_snapshot(model, as_of))
    if (k_grid[j] == 100) baseline <- model$updates
    if (progress && (j %% 25L == 0L || j == length(k_grid))) {
      message(unique(matches$format), ": replayed ", j, "/", length(k_grid), " candidates")
    }
  }
  list(
    matches = matches, k_grid = k_grid, predictions = predictions,
    ratings = do.call(rbind, ratings), baseline = baseline
  )
}

select_elo_k <- function(replay, origin, window, minimum_matches = 100L, omit_year = NULL) {
  year <- as.integer(format(origin, "%Y"))
  years <- seq.int(year - window, year - 1L)
  if (!is.null(omit_year)) years <- setdiff(years, omit_year)
  match_year <- as.integer(format(replay$matches$start_date, "%Y"))
  rows <- match_year %in% years & replay$matches$end_date < origin
  n <- sum(rows)
  supported <- n >= minimum_matches && all(years %in% match_year[rows])
  if (!supported) {
    return(list(supported = FALSE, n = n, k = NA_real_, curve = NULL))
  }
  mse <- colMeans((replay$predictions[rows, , drop = FALSE] - replay$matches$score[rows])^2)
  best <- order(mse, replay$k_grid)[1]
  list(supported = TRUE, n = n, k = replay$k_grid[best], curve = data.frame(k = replay$k_grid, mse = mse))
}

select_production_elo_k <- function(matches, as_of, specification = elo_tuning_specification()) {
  origin <- as.Date(paste0(format(as_of, "%Y"), "-01-01"))
  selections <- curves <- list()
  for (name in sort(unique(matches$format))) {
    replay <- replay_elo_grid(matches[matches$format == name, ], specification$k_grid, origin - 1L)
    choice <- select_elo_k(replay, origin, specification$primary_window, specification$minimum_matches)
    if (!choice$supported) stop("Insufficient prior-year data to select K for ", name)
    selections[[name]] <- data.frame(
      format = name, k = choice$k, origin = origin,
      tuning_start = as.Date(paste0(as.integer(format(origin, "%Y")) - specification$primary_window, "-01-01")),
      tuning_end = origin - 1L, n_tuning = choice$n, mse = min(choice$curve$mse),
      boundary = choice$k %in% range(specification$k_grid)
    )
    curves[[name]] <- cbind(format = name, choice$curve)
  }
  selections <- do.call(rbind, selections)
  rownames(selections) <- NULL
  list(
    k = setNames(selections$k, selections$format), selections = selections, curves = do.call(rbind, curves),
    specification = list(
      method = "annual chronological expected-score MSE selection", origin = as.character(origin),
      window_years = specification$primary_window, minimum_matches = specification$minimum_matches,
      k_grid = specification$k_grid, objective = specification$objective,
      prediction = specification$prediction, tie_break = "smaller K",
      history = "full-history replay at the currently selected K; not historical live forecasts"
    )
  )
}

evaluate_elo_tuning <- function(replay, as_of, specification = elo_tuning_specification()) {
  matches <- replay$matches
  final_year <- as.integer(format(as_of, "%Y"))
  if (final_year < specification$first_evaluation_year) stop("Cutoff precedes the evaluation period")
  years <- seq.int(specification$first_evaluation_year, final_year)
  match_year <- as.integer(format(matches$start_date, "%Y"))
  baseline <- replay$predictions[, match(100, replay$k_grid)]
  folds <- tuning <- evaluation <- list()
  for (window in specification$windows) {
    for (year in years) {
      origin <- as.Date(paste0(year, "-01-01"))
      choice <- select_elo_k(replay, origin, window, specification$minimum_matches)
      rows <- which(match_year == year)
      selected <- if (choice$supported) replay$predictions[rows, match(choice$k, replay$k_grid)] else numeric()
      folds[[length(folds) + 1L]] <- data.frame(
        window = window, year = year, origin = origin, tuning_start = as.Date(paste0(year - window, "-01-01")),
        supported = choice$supported, n_tuning = choice$n, selected_k = choice$k,
        boundary = choice$supported && choice$k %in% range(replay$k_grid),
        n_evaluation = length(rows), partial_year = as_of < as.Date(paste0(year, "-12-31")),
        tuned_mse = if (length(selected)) mean((matches$score[rows] - selected)^2) else NA_real_,
        baseline_mse = if (length(rows)) mean((matches$score[rows] - baseline[rows])^2) else NA_real_,
        neutral_mse = if (length(rows)) mean((matches$score[rows] - 0.5)^2) else NA_real_
      )
      if (!choice$supported) next
      tuning[[length(tuning) + 1L]] <- cbind(window = window, year = year, n = choice$n, choice$curve)
      if (!length(rows)) next
      evaluation[[length(evaluation) + 1L]] <- data.frame(
        window = window, year = year, selected_k = choice$k,
        matches[rows, c("match_id", "start_date", "end_date", "team1", "team2", "score")],
        expected_score = selected, baseline_score = baseline[rows],
        squared_error = (matches$score[rows] - selected)^2,
        baseline_error = (matches$score[rows] - baseline[rows])^2,
        neutral_error = (matches$score[rows] - 0.5)^2
      )
    }
  }
  folds <- do.call(rbind, folds)
  tuning <- do.call(rbind, tuning)
  evaluation <- do.call(rbind, evaluation)
  if (is.null(evaluation)) stop("No supported evaluation folds")
  common_years <- Reduce(intersect, lapply(specification$windows, function(window) {
    folds$year[folds$window == window & folds$supported & folds$n_evaluation > 0L]
  }))
  summary <- list()
  for (scope in c("available", "common")) {
    for (window in specification$windows) {
      rows <- evaluation[evaluation$window == window, ]
      if (scope == "common") rows <- rows[rows$year %in% common_years, ]
      if (!nrow(rows)) next
      annual <- aggregate(rows$squared_error - rows$baseline_error, list(year = rows$year), mean)
      summary[[length(summary) + 1L]] <- data.frame(
        scope = scope, window = window, n = nrow(rows), years = nrow(annual),
        first_year = min(rows$year), last_year = max(rows$year),
        tuned_mse = mean(rows$squared_error), baseline_mse = mean(rows$baseline_error),
        neutral_mse = mean(rows$neutral_error), difference = mean(rows$squared_error - rows$baseline_error),
        years_better = sum(annual$x < 0), years_equal = sum(annual$x == 0)
      )
    }
  }
  current <- folds[folds$year == final_year & folds$window == specification$primary_window, ]
  if (!current$supported) stop("Insufficient data for the primary current selection")
  curve <- tuning[tuning$year == final_year & tuning$window == specification$primary_window, ]
  curve$near_minimum <- curve$mse <= min(curve$mse) + specification$near_minimum_mse
  current$tuning_mse <- min(curve$mse)
  current$near_minimum_low <- min(curve$k[curve$near_minimum])
  current$near_minimum_high <- max(curve$k[curve$near_minimum])
  current$near_minimum_count <- sum(curve$near_minimum)
  stability <- year_curves <- list()
  for (year in seq.int(final_year - specification$primary_window, final_year - 1L)) {
    rows <- match_year == year & matches$end_date < current$origin
    year_curves[[length(year_curves) + 1L]] <- data.frame(
      year = year, k = replay$k_grid, n = sum(rows),
      mse = colMeans((replay$predictions[rows, , drop = FALSE] - matches$score[rows])^2)
    )
    choice <- select_elo_k(replay, current$origin, specification$primary_window,
      specification$minimum_matches,
      omit_year = year
    )
    stability[[length(stability) + 1L]] <- data.frame(
      omitted_year = year, supported = choice$supported, n = choice$n, selected_k = choice$k
    )
  }
  ratings <- replay$ratings
  ratings$is_selected <- ratings$k == current$selected_k
  ratings$is_near_minimum <- ratings$k %in% curve$k[curve$near_minimum]
  list(
    tuning = tuning, folds = folds, evaluation = evaluation, summary = do.call(rbind, summary),
    current_selection = current, current_curve = curve, year_curves = do.call(rbind, year_curves),
    stability = do.call(rbind, stability), ratings = ratings
  )
}

elo_tuning_report <- function(result, format, as_of, path) {
  current <- result$current_selection
  primary <- result$summary[result$summary$scope == "available" & result$summary$window == current$window, ]
  leaders <- result$ratings[result$ratings$is_selected & result$ratings$is_active, c("rank", "team", "rating")]
  leaders <- head(leaders[order(leaders$rank), ], 10L)
  show_table <- function(table) as.character(knitr::kable(table, format = "pipe", row.names = FALSE, digits = 5))
  text <- c(
    paste0("# ", format, " Elo K selection through ", as_of), "",
    sprintf("Primary policy: select K each January using the preceding %d complete years.", current$window),
    sprintf(
      "Current selection: **K = %s**, using cutoff %s and %d tuning matches.",
      current$selected_k, current$origin, current$n_tuning
    ), "",
    sprintf(
      "Across %d evaluation matches in %d years, mean squared error was %.5f versus %.5f at K = 100.",
      primary$n, primary$years, primary$tuned_mse, primary$baseline_mse
    ),
    sprintf(
      "The selected policy did better in %d of %d evaluation years (%d exact ties).",
      primary$years_better, primary$years, primary$years_equal
    ), "",
    "These are retrospective forecasts with chronological separation, not blinded confirmation.",
    "Squared error measures expected-score accuracy, not three-outcome probability accuracy.",
    "The production pipeline uses the same five-year selection rule.", "",
    "## Evaluation and tuning-window sensitivity", "",
    show_table(result$summary), "",
    "Available rows use each policy's supported folds; common rows use their intersection.",
    "The final year can be partial. Each match has equal weight; annual differences are dependent.", "",
    "## Annual primary evaluation", "",
    show_table(result$folds[
      result$folds$window == current$window,
      c("year", "supported", "selected_k", "n_tuning", "n_evaluation", "partial_year", "tuned_mse", "baseline_mse")
    ]), "",
    "Unsupported means too few tuning matches or at least one tuning year with no eligible results.", "",
    "## How precisely is current K determined?", "",
    sprintf(
      "%d candidates lie within 0.001 MSE of the minimum; their endpoints are %s and %s.",
      current$near_minimum_count, current$near_minimum_low, current$near_minimum_high
    ),
    "This is a descriptive tolerance, not a confidence interval. Consult current_curve.csv for membership.",
    "Leaving out one tuning year at a time gives:", "", show_table(result$stability), "",
    if (current$boundary) {
      "The selected K is a search endpoint; do not claim an interior optimum."
    } else {
      "The current selection is inside the search grid."
    },
    "K = 1 cannot learn from equal initial integer ratings: half-point changes round back to 1,000.", "",
    "## Current candidate ratings", "", show_table(leaders), "",
    "These replay the full history at the current selected K and update through the stated cutoff.",
    "Each candidate replays the full history at one K; annual K choices are not spliced together.",
    "ratings.csv contains every candidate, including flags for near-minimum choices.", "",
    "## Reproduction and limitations", "",
    "Run `make tune-elo` and `make visualize-elo-tuning` from the repository root.",
    "The manifest records settings and hashes; candidate_predictions.csv.gz retains the forecasts.",
    "Methods and reproduction: [pipeline guide](../../../../docs/pipeline.md#selecting-k).", "",
    "No-results are excluded. All forecasts exclude results completed on or after the match's start date.",
    "The primary model omits venue, lineup, margin and inactivity effects; changing K cannot repair those omissions.",
    "Historical data revisions and opponent mix can affect the results.",
    "Later data are needed for prospective confirmation."
  )
  writeLines(text, path)
}

run_elo_tuning <- function(format = NULL) {
  specification <- elo_tuning_specification()
  sources <- c(
    "R/elo.R", "R/pipeline.R", "R/models/common.R", "R/models/elo_tuning.R",
    "scripts/models.R", "docs/pipeline.md", "renv.lock", "data/build/manifest.json"
  )
  source_hashes <- as.list(setNames(vapply(sources, sha256, character(1)), sources))
  prepared <- read_prepared("data/build")
  as_of <- as.Date(prepared$manifest$as_of)
  available <- sort(unique(prepared$matches$format))
  if (is.null(format)) format <- available
  if (!length(format) || any(!format %in% available)) stop("Unknown format")
  for (name in format) {
    output <- file.path("out/analysis/elo_tuning", tolower(name))
    replace_model_directory(output, function(directory) {
      matches <- prepared$matches[prepared$matches$format == name, ]
      coverage <- data.frame(
        year = as.integer(format(matches$start_date, "%Y")), total = 1L,
        rated = as.integer(!is.na(matches$score)), no_result = as.integer(is.na(matches$score)),
        draw_tie = as.integer(!is.na(matches$score) & matches$score == 0.5)
      )
      coverage <- aggregate(coverage[-1], coverage[1], sum)
      replay <- replay_elo_grid(matches, specification$k_grid, as_of, progress = TRUE)
      reference <- fit_elo(matches)$updates
      stopifnot(identical(replay$baseline, reference))
      published_verified <- FALSE
      publication <- "out/release/elo"
      if (file.exists(file.path(publication, "manifest.json"))) {
        manifest <- jsonlite::read_json(file.path(publication, "manifest.json"))
        if (identical(manifest$analysis$input_sha256, prepared$manifest$matches_sha256)) {
          ledger_path <- file.path(publication, "updates.csv")
          if (!identical(sha256(ledger_path), manifest$files$updates.csv)) stop("Published ledger checksum mismatch")
          ledger <- readr::read_csv(ledger_path, show_col_types = FALSE)
          ledger <- as.data.frame(ledger[ledger$format == name, ])
          rownames(ledger) <- NULL
          published_k <- manifest$analysis$specification$k
          if (is.list(published_k)) published_k <- published_k[[name]]
          published_reference <- fit_elo(matches, k = published_k)$updates
          stopifnot(isTRUE(all.equal(published_reference, ledger[names(published_reference)])))
          published_verified <- TRUE
        }
      }
      result <- evaluate_elo_tuning(replay, as_of, specification)
      result$coverage <- coverage
      for (table in names(result)) {
        rows <- result[[table]]
        if (!"format" %in% names(rows)) rows <- cbind(format = name, rows)
        if (anyDuplicated(names(rows)) || any(rows$format != name)) stop("Invalid output table: ", table)
        readr::write_csv(rows, file.path(directory, paste0(table, ".csv")), na = "")
      }
      first_year <- specification$first_evaluation_year - max(specification$windows)
      rows <- replay$matches$start_date >= as.Date(paste0(first_year, "-01-01"))
      forecasts <- do.call(rbind, lapply(seq_along(replay$k_grid), function(j) {
        data.frame(
          k = replay$k_grid[j],
          replay$matches[rows, c("match_id", "format", "start_date", "end_date", "team1_id", "team2_id", "score")],
          expected_score = replay$predictions[rows, j]
        )
      }))
      readr::write_csv(forecasts, file.path(directory, "candidate_predictions.csv.gz"))
      elo_tuning_report(result, name, as_of, file.path(directory, "report.md"))
      if (
        !identical(source_hashes, as.list(setNames(vapply(sources, sha256, character(1)), sources))) ||
          !identical(sha256("data/build/matches.csv"), prepared$manifest$matches_sha256)
      ) {
        stop("Inputs, code or analysis plan changed during tuning; rerun with a stable source tree")
      }
      files <- list.files(directory, full.names = TRUE)
      write_json(list(
        format = name, as_of = as.character(as_of), specification = specification,
        input_sha256 = prepared$manifest$matches_sha256, baseline_specification = elo_specification(),
        r_version = as.character(getRversion()), publication_ledger_verified = published_verified,
        code_sha256 = source_hashes,
        files = as.list(setNames(vapply(files, sha256, character(1)), basename(files)))
      ), file.path(directory, "manifest.json"))
      message(name, ": selected K = ", result$current_selection$selected_k, "; saved ", output)
    })
  }
  invisible(NULL)
}

check_elo_tuning <- function(directory) {
  manifest <- jsonlite::read_json(file.path(directory, "manifest.json"))
  for (file in names(manifest$files)) {
    if (basename(file) != file || !identical(sha256(file.path(directory, file)), manifest$files[[file]])) {
      stop("Tuning output checksum mismatch: ", file)
    }
  }
  read <- function(name) as.data.frame(readr::read_csv(file.path(directory, name), show_col_types = FALSE))
  predictions <- read("candidate_predictions.csv.gz")
  tuning <- read("tuning.csv")
  folds <- read("folds.csv")
  evaluation <- read("evaluation.csv")
  summary <- read("summary.csv")
  current <- read("current_selection.csv")
  ratings <- read("ratings.csv")
  equal <- function(actual, expected) {
    if (!isTRUE(all.equal(as.numeric(actual), as.numeric(expected), tolerance = 1e-12))) {
      stop("Saved tuning values disagree with reconstructed forecasts")
    }
  }
  key <- paste(predictions$k, predictions$match_id)
  if (
    anyDuplicated(key) || anyNA(predictions$expected_score) ||
      any(predictions$expected_score < 0 | predictions$expected_score > 1)
  ) {
    stop("Invalid saved forecasts")
  }
  grid <- unlist(manifest$specification$k_grid)
  if (!length(grid) || !setequal(unique(predictions$k), grid) || any(table(predictions$match_id) != length(grid))) {
    stop("Incomplete candidate grid in saved forecasts")
  }
  if (anyDuplicated(paste(evaluation$window, evaluation$match_id))) stop("Duplicate evaluation forecasts")
  baseline_rows <- predictions[predictions$k == 100, ]
  baseline_year <- as.integer(format(baseline_rows$start_date, "%Y"))
  losses <- (predictions$score - predictions$expected_score)^2
  match_year <- as.integer(format(predictions$start_date, "%Y"))
  for (i in which(folds$supported)) {
    fold <- folds[i, ]
    rows <- predictions$start_date >= fold$tuning_start & predictions$end_date < fold$origin
    expected <- aggregate(losses[rows], list(k = predictions$k[rows]), mean)
    counts <- table(predictions$k[rows])
    recorded <- tuning[tuning$window == fold$window & tuning$year == fold$year, ]
    if (anyDuplicated(recorded$k) || !setequal(recorded$k, grid)) stop("Incomplete tuning curve")
    expected <- expected[match(recorded$k, expected$k), ]
    equal(recorded$mse, expected$x)
    equal(recorded$n, as.numeric(counts[as.character(recorded$k)]))
    equal(fold$selected_k, expected$k[order(expected$x, expected$k)[1]])
    equal(fold$n_tuning, unique(recorded$n))
    evaluated <- evaluation[evaluation$window == fold$window & evaluation$year == fold$year, ]
    if (!setequal(evaluated$match_id, baseline_rows$match_id[baseline_year == fold$year])) {
      stop("Incomplete evaluation fold")
    }
    equal(fold$n_evaluation, nrow(evaluated))
    if (nrow(evaluated)) {
      equal(fold$tuned_mse, mean(evaluated$squared_error))
      equal(fold$baseline_mse, mean(evaluated$baseline_error))
      equal(fold$neutral_mse, mean(evaluated$neutral_error))
      equal(unique(evaluated$selected_k), fold$selected_k)
    }
  }
  selected <- match(paste(evaluation$selected_k, evaluation$match_id), key)
  baseline <- match(paste(100, evaluation$match_id), key)
  if (anyNA(selected) || anyNA(baseline)) stop("Evaluation forecasts missing from candidate ledger")
  equal(evaluation$expected_score, predictions$expected_score[selected])
  equal(evaluation$baseline_score, predictions$expected_score[baseline])
  equal(evaluation$score, predictions$score[selected])
  equal(evaluation$year, match_year[selected])
  equal(evaluation$squared_error, losses[selected])
  equal(evaluation$baseline_error, losses[baseline])
  equal(evaluation$neutral_error, (evaluation$score - 0.5)^2)
  common <- Reduce(intersect, lapply(split(evaluation$year, evaluation$window), unique))
  for (i in seq_len(nrow(summary))) {
    row <- summary[i, ]
    rows <- evaluation[evaluation$window == row$window, ]
    if (row$scope == "common") rows <- rows[rows$year %in% common, ]
    equal(row$n, nrow(rows))
    equal(row$years, length(unique(rows$year)))
    equal(row$tuned_mse, mean(rows$squared_error))
    equal(row$baseline_mse, mean(rows$baseline_error))
    equal(row$neutral_mse, mean(rows$neutral_error))
    equal(row$difference, mean(rows$squared_error - rows$baseline_error))
  }
  equal(current$selected_k, folds$selected_k[folds$year == current$year & folds$window == current$window])
  equal(ratings$is_selected, ratings$k == current$selected_k)
  message(manifest$format, ": saved candidate forecasts, tuning choices, annual losses and summaries verified")
  invisible(TRUE)
}
