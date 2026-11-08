venue_mapping <- function() {
  data.frame(
    ground_profile_id = 99L, ground_label = "Example", country = "India",
    valid_from = as.Date("2020-01-01"), valid_until = as.Date("2021-01-01"),
    source = "https://example.org/venue", method = "verified_location"
  )
}

venue_matches <- function(matches) {
  matches$ground_profile_id <- c(99L, 99L, 100L, 99L)
  matches$start_date <- as.Date("2020-02-01") + 0:3
  matches$team1 <- c("India", "England", "India", "India")
  matches$team2 <- c("Australia", "Australia", "Australia", "Australia")
  matches$country <- c(NA_character_, NA_character_, NA_character_, "India")
  matches$home_sign <- c(NA_integer_, NA_integer_, NA_integer_, 1L)
  matches$context_source <- c(NA_character_, NA_character_, NA_character_, "existing source")
  matches
}

test_that("venue resolution conserves matches and distinguishes neutral and unknown", {
  matches <- venue_matches(simulated_matches(4L))
  result <- resolve_ground_jurisdictions(matches, venue_mapping())
  expect_identical(result$match_id, matches$match_id)
  expect_equal(nrow(result), nrow(matches))
  expect_equal(result$score, matches$score)
  expect_equal(result$country_original, matches$country)
  expect_equal(result$home_sign_original, matches$home_sign)
  expect_equal(result$country, c("India", "India", NA_character_, "India"))
  expect_equal(result$home_sign, c(1L, 0L, NA_integer_, 1L))
  expect_equal(result$venue_resolution, c("verified_location", "verified_location", "unresolved", "existing"))
  expect_equal(result$venue_source[1:2], rep("https://example.org/venue", 2))
  expect_equal(result$context_source[4], "existing source")
  expect_true(is.na(result$venue_source[4]))
})

test_that("venue mappings respect dates and reject overlap or disagreement", {
  matches <- venue_matches(simulated_matches(4L))
  matches$start_date[1:2] <- as.Date(c("2019-12-31", "2021-01-01"))
  result <- resolve_ground_jurisdictions(matches, venue_mapping())
  expect_true(all(is.na(result$country[1:2])))
  mapping <- venue_mapping()
  expect_error(resolve_ground_jurisdictions(matches, rbind(mapping, mapping)), "Overlapping")
  matches$country[4] <- "Australia"
  expect_error(resolve_ground_jurisdictions(matches, mapping), "conflicts")
  mapping$valid_until <- mapping$valid_from
  expect_error(resolve_ground_jurisdictions(matches, mapping), "validity dates")
})

test_that("venue resolution requires unique matches and complete evidence", {
  matches <- venue_matches(simulated_matches(4L))
  expect_error(resolve_ground_jurisdictions(rbind(matches, matches[1, ]), venue_mapping()), "unique match")
  mapping <- venue_mapping()
  mapping$country <- NA_character_
  expect_error(resolve_ground_jurisdictions(matches, mapping), "Incomplete")
  mapping <- venue_mapping()
  mapping$source <- ""
  expect_error(resolve_ground_jurisdictions(matches, mapping), "evidence")
  mapping <- venue_mapping()
  mapping$method <- "guess from winner"
  expect_error(resolve_ground_jurisdictions(matches, mapping), "evidence")
})

test_that("all current formats retain their requested sample after verified venue resolution", {
  matches <- simulated_matches(100L)
  matches$country <- NA_character_
  matches$home_sign <- NA_integer_
  matches$context_source <- NA_character_
  matches$ground_profile_id <- 99L
  mapping <- venue_mapping()
  mapping$valid_from <- min(matches$start_date)
  mapping$valid_until <- max(matches$end_date) + 1L
  result <- resolve_ground_jurisdictions(matches, mapping)
  for (name in c("Test", "ODI", "T20I")) {
    result$format <- name
    train <- current_training(result, name, max(result$end_date))
    expect_equal(nrow(train), nrow(matches))
    expect_setequal(train$match_id, matches$match_id)
    expect_false(anyNA(train$country))
  }
})

test_that("ground bridge snapshots require a pinned source and intact content", {
  directory <- tempfile()
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE))
  mapping <- venue_mapping()
  path <- file.path(directory, "grounds.csv")
  readr::write_csv(mapping, path)
  ref <- paste(rep("a", 40), collapse = "")
  manifest <- list(source = ground_bridge_url(ref), source_commit = ref, sha256 = sha256(path))
  write_json(manifest, file.path(directory, "manifest.json"))
  expect_equal(as.data.frame(read_ground_bridge(directory)), mapping)
  expect_error(ground_bridge_url("main"), "full commit SHA")
  expect_error(ground_bridge_url(character()), "full commit SHA")
  manifest$source <- "https://example.org/grounds.csv"
  write_json(manifest, file.path(directory, "manifest.json"))
  expect_error(read_ground_bridge(directory), "source or checksum")
  manifest$source <- ground_bridge_url(ref)
  write_json(manifest, file.path(directory, "manifest.json"))
  mapping$country <- "Australia"
  readr::write_csv(mapping, path)
  expect_error(read_ground_bridge(directory), "source or checksum")
})

test_that("all supported bridge methods preserve their provenance", {
  matches <- venue_matches(simulated_matches(4L))
  for (method in c("legacy_match_link", "audited_jurisdiction", "verified_location")) {
    mapping <- venue_mapping()
    mapping$method <- method
    result <- resolve_ground_jurisdictions(matches, mapping)
    expect_equal(result$country[1:2], c("India", "India"))
    expect_equal(result$venue_resolution[1:2], rep(method, 2))
    expect_equal(result$venue_source[1:2], rep(mapping$source, 2))
  }
  mapping <- venue_mapping()
  mapping$ground_profile_id <- 0L
  expect_error(validate_ground_mapping(mapping), "Invalid ground profile")
})
