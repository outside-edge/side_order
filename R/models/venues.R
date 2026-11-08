read_context_matches <- function(path) {
  readr::read_csv(path, col_types = readr::cols(
    match_id = readr::col_integer(), format = readr::col_character(),
    start_date = readr::col_date(), end_date = readr::col_date(),
    team1_id = readr::col_integer(), team2_id = readr::col_integer(),
    score = readr::col_double(), ground_profile_id = readr::col_integer(),
    home_sign = readr::col_integer(), .default = readr::col_character()
  ))
}

resolve_ground_jurisdictions <- function(matches, mapping) {
  required <- c("ground_profile_id", "ground_label", "country", "valid_from", "valid_until", "source", "method")
  if (!all(required %in% names(mapping)) || anyNA(mapping[required])) stop("Incomplete venue mapping")
  if (anyDuplicated(matches$match_id)) stop("Venue resolution requires unique match IDs")
  if (
    !inherits(mapping$valid_from, "Date") || !inherits(mapping$valid_until, "Date") ||
      any(mapping$valid_until <= mapping$valid_from)
  ) stop("Invalid venue validity dates")
  if (
    any(!nzchar(trimws(mapping$country))) || any(!grepl("^https://", mapping$source)) ||
      any(mapping$method != "verified_location")
  ) stop("Invalid venue mapping evidence")
  for (id in unique(mapping$ground_profile_id)) {
    periods <- mapping[mapping$ground_profile_id == id, ]
    periods <- periods[order(periods$valid_from), ]
    if (nrow(periods) > 1L && any(head(periods$valid_until, -1) > tail(periods$valid_from, -1))) {
      stop("Overlapping venue mapping periods")
    }
  }
  result <- matches
  result$country_original <- matches$country
  result$home_sign_original <- matches$home_sign
  result$venue_resolution <- ifelse(is.na(matches$country), "unresolved", "existing")
  result$venue_source <- NA_character_
  for (i in seq_len(nrow(mapping))) {
    rows <- which(
      matches$ground_profile_id == mapping$ground_profile_id[i] &
        matches$start_date >= mapping$valid_from[i] & matches$start_date < mapping$valid_until[i]
    )
    country <- normalize_jurisdiction(mapping$country[i])
    if (any(!is.na(matches$country[rows]) & matches$country[rows] != country)) {
      stop("Venue mapping conflicts with an existing country")
    }
    rows <- rows[is.na(matches$country[rows])]
    result$country[rows] <- country
    result$venue_resolution[rows] <- mapping$method[i]
    result$venue_source[rows] <- mapping$source[i]
    result$context_source[rows] <- "verified location via ground profile ID"
  }
  result$home_sign <- as.integer(normalize_jurisdiction(result$team1) == result$country) -
    as.integer(normalize_jurisdiction(result$team2) == result$country)
  stopifnot(identical(matches$match_id, result$match_id), nrow(matches) == nrow(result))
  result
}

prepare_model_venues <- function() {
  validate_model_context()
  matches <- read_context_matches("data/context/matches.csv")
  mapping <- readr::read_csv("data/reference/ground_jurisdictions.csv", col_types = readr::cols(
    ground_profile_id = readr::col_integer(), valid_from = readr::col_date(),
    valid_until = readr::col_date(), .default = readr::col_character()
  ))
  result <- resolve_ground_jurisdictions(matches, mapping)
  invitational <- c("ICC World XI", "World-XI", "Asia XI", "Africa XI")
  eligible <- result$start_date >= as.Date("2000-01-01") & !is.na(result$score) &
    !result$team1 %in% invitational & !result$team2 %in% invitational
  sample <- result[eligible, ]
  coverage <- aggregate(cbind(
    eligible_matches = rep(1L, nrow(sample)), originally_known = as.integer(!is.na(sample$country_original)),
    resolved = as.integer(sample$venue_resolution == "verified_location"),
    unresolved = as.integer(is.na(sample$country))
  ), list(format = sample$format), sum)
  legacy <- readr::read_csv("data/cricket_matches.csv", col_types = readr::cols(.default = readr::col_character()))
  missing <- sample[is.na(sample$country_original), ]
  index <- match(missing$match_id, legacy$match_id)
  missing$legacy_ground <- legacy$ground[index]
  missing$mapping_gap <- ifelse(is.na(index), "no_legacy_match_anchor", "legacy_ground_not_mapped")
  replace_directory("data/context/resolved", function(output) {
    readr::write_csv(result, file.path(output, "matches.csv"), na = "")
    readr::write_csv(coverage, file.path(output, "coverage.csv"))
    readr::write_csv(missing[c(
      "match_id", "format", "start_date", "ground_profile_id", "ground_label", "legacy_ground", "mapping_gap",
      "country_original", "country", "home_sign_original", "home_sign", "venue_resolution", "venue_source"
    )], file.path(output, "venue_audit.csv"), na = "")
    inputs <- c(
      "data/context/matches.csv", "data/context/manifest.json", "data/cricket_matches.csv",
      "data/reference/ground_jurisdictions.csv", "R/models/venues.R"
    )
    files <- list.files(output, full.names = TRUE)
    write_json(list(
      inputs = as.list(setNames(vapply(inputs, sha256, character(1)), inputs)),
      files = as.list(setNames(vapply(files, sha256, character(1)), basename(files))),
      rows = nrow(result), policy = "Preserve all rows; fill only missing countries using dated verified locations",
      eligibility = "Completed scored national-team matches starting in 2000 or later; no invitational XIs"
    ), file.path(output, "manifest.json"))
  })
  print(coverage)
  invisible(result)
}

read_resolved_model_context <- function() {
  validate_model_context()
  path <- "data/context/resolved"
  manifest <- jsonlite::read_json(file.path(path, "manifest.json"))
  for (name in names(manifest$inputs)) {
    if (!file.exists(name) || sha256(name) != manifest$inputs[[name]]) stop("Run make resolve-model-venues: ", name)
  }
  for (name in names(manifest$files)) {
    if (basename(name) != name || sha256(file.path(path, name)) != manifest$files[[name]]) {
      stop("Resolved venue checksum mismatch: ", name)
    }
  }
  read_context_matches(file.path(path, "matches.csv"))
}
