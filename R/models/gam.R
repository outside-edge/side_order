gam_inputs <- function(matches, levels, margin) {
  n <- nrow(matches)
  team <- factor(c(as.character(matches$team1_id), as.character(matches$team2_id)), levels = levels$team)
  if (anyNA(team)) stop("GAM prediction requires teams represented in training")
  dim(team) <- c(n, 2L)
  country <- factor(matches$country, levels = levels$country)
  ground <- factor(as.character(matches$ground_profile_id), levels = levels$ground)
  country_known <- !is.na(country)
  ground_known <- !is.na(ground)
  country[!country_known] <- levels$country[1]
  ground[!ground_known] <- levels$ground[1]
  list(
    y = outcome_category(matches$score),
    time = matrix(rep(as.numeric(matches$start_date - as.Date("2000-01-01")) / 365.25, 2L), n, 2L),
    team = team, signs = matrix(rep(c(1, -1), each = n), n, 2L),
    home = matches$home_sign, country = country, ground = ground,
    country_home = matches$home_sign * country_known, ground_home = matches$home_sign * ground_known,
    shift = rep(margin - 1, n)
  )
}

fit_spline <- function(matches, margin, k = 6L) {
  levels <- list(
    team = sort(unique(as.character(c(matches$team1_id, matches$team2_id)))),
    country = sort(unique(matches$country)), ground = sort(unique(as.character(matches$ground_profile_id)))
  )
  inputs <- gam_inputs(matches, levels, margin)
  terms <- c("s(time, team, bs = 'fs', by = signs, k = k)", "home", "offset(shift)")
  if (length(levels$country) > 1L) terms <- c(terms, "s(country, bs = 're', by = country_home)")
  if (length(levels$ground) > 1L) terms <- c(terms, "s(ground, bs = 're', by = ground_home)")
  formula <- as.formula(paste("y ~ 0 +", paste(terms, collapse = " + ")))
  model <- mgcv::gam(
    formula,
    data = inputs, family = mgcv::ocat(theta = 2 * margin, R = 3), method = "REML"
  )
  if (!isTRUE(model$converged)) stop("GAM did not converge")
  list(model = model, levels = levels, margin = margin, k = k, last_date = max(matches$start_date))
}

predict_spline <- function(model, matches) {
  matches$start_date <- pmin(matches$start_date, model$last_date)
  p <- predict(model$model, newdata = gam_inputs(matches, model$levels, model$margin), type = "response")
  check_probabilities(p)
  p
}

select_spline <- function(train, origin, k = 6L) {
  inner_origin <- previous_year(origin)
  earlier <- train[train$end_date < inner_origin, ]
  validation <- train[train$start_date >= inner_origin, ]
  teams <- unique(c(earlier$team1_id, earlier$team2_id))
  validation <- validation[validation$team1_id %in% teams & validation$team2_id %in% teams, ]
  if (nrow(earlier) < 50 || !nrow(validation)) stop("Insufficient inner validation data")
  grid <- draw_grid(unique(train$format))
  scores <- vapply(grid, function(margin) {
    message("GAM validation: margin = ", margin, ", matches = ", nrow(earlier))
    fit <- fit_spline(earlier, margin, k)
    probability_metrics(predict_spline(fit, validation), validation$score)$log_loss
  }, numeric(1))
  selected <- grid[which.min(scores)]
  message("GAM full fit: margin = ", selected, ", matches = ", nrow(train))
  list(fit = fit_spline(train, selected, k), tuning = data.frame(margin = grid, log_loss = scores))
}
