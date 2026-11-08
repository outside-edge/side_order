normalize_jurisdiction <- function(x) {
  x <- trimws(x)
  aliases <- c(
    "U.A.E." = "United Arab Emirates", "U.S.A." = "United States of America",
    "P.N.G." = "Papua New Guinea", "Cayman" = "Cayman Islands", "Czech Rep." = "Czech Republic",
    "Swaziland" = "Eswatini"
  )
  replace <- match(x, names(aliases))
  x[!is.na(replace)] <- unname(aliases[replace[!is.na(replace)]])
  x
}

match_ground_profiles <- function(raw_dir) {
  paths <- list.files(raw_dir, pattern = "\\.html\\.gz$", recursive = TRUE, full.names = TRUE)
  records <- lapply(paths, function(path) {
    cached <- read_page(path)
    parsed <- parse_page(cached$content, cached$receipt$format, cached$receipt$year)
    if (!nrow(parsed)) {
      return(NULL)
    }
    page <- xml2::read_html(cached$content)
    tables <- rvest::html_elements(page, "table.engineTable")
    captions <- rvest::html_text2(rvest::html_element(tables, "caption"))
    rows <- rvest::html_elements(tables[!is.na(captions) & captions == "Match results"], "tr.data1")
    grounds <- lapply(rows, function(row) {
      cells <- rvest::html_elements(row, "td")
      cell <- cells[length(cells) - 2L]
      link <- rvest::html_elements(cell, "a[href*='/ground/']")
      if (length(link) != 1L) stop("Missing or ambiguous ground profile in ", path)
      href <- rvest::html_attr(link, "href")
      if (!grepl("/ground/[0-9]+\\.html$", href)) stop("Invalid ground profile")
      data.frame(
        ground_profile_id = as.integer(sub(".*/ground/([0-9]+)\\.html$", "\\1", href)),
        ground_label = rvest::html_text2(link)
      )
    })
    cbind(parsed["match_id"], do.call(rbind, grounds))
  })
  records <- unique(do.call(rbind, records))
  if (anyDuplicated(records$match_id)) stop("Conflicting ground records for a match")
  records
}

join_match_context <- function(matches, profiles, legacy, grounds, periods = NULL) {
  if (anyDuplicated(matches$match_id) || anyDuplicated(profiles$match_id) || anyDuplicated(legacy$match_id)) {
    stop("Context joins require unique match IDs")
  }
  grounds$ground <- trimws(grounds$ground)
  grounds$country <- normalize_jurisdiction(grounds$country)
  mapping <- unique(grounds[c("ground", "country")])
  mapping <- mapping[!is.na(mapping$country) & nzchar(mapping$country), ]
  if (anyDuplicated(mapping$ground)) stop("Conflicting countries for a ground name")
  old <- legacy[match(matches$match_id, legacy$match_id), ]
  same <- normalize_jurisdiction(matches$team1) == normalize_jurisdiction(old$team1) &
    normalize_jurisdiction(matches$team2) == normalize_jurisdiction(old$team2)
  reverse <- normalize_jurisdiction(matches$team1) == normalize_jurisdiction(old$team2) &
    normalize_jurisdiction(matches$team2) == normalize_jurisdiction(old$team1)
  matched <- !is.na(old$match_id)
  if (any(matched & !(same | reverse), na.rm = TRUE)) stop("Legacy participants disagree with canonical matches")
  if (any(matched & (is.na(same) | is.na(reverse)))) stop("Missing legacy participants")
  profiles <- profiles[match(matches$match_id, profiles$match_id), ]
  if (anyNA(profiles$match_id)) stop("Missing match ground profile")
  country <- mapping$country[match(trimws(old$ground), mapping$ground)]
  crosswalk <- unique(data.frame(ground_profile_id = profiles$ground_profile_id, country = country))
  crosswalk <- crosswalk[!is.na(crosswalk$country), ]
  if (!is.null(periods)) {
    periods$country <- normalize_jurisdiction(periods$country)
    crosswalk <- crosswalk[!crosswalk$ground_profile_id %in% periods$ground_profile_id, ]
  }
  if (anyDuplicated(crosswalk$ground_profile_id)) stop("Conflicting countries for a ground profile")
  crosswalk$valid_from <- rep(as.Date("1877-01-01"), nrow(crosswalk))
  crosswalk$valid_until <- rep(as.Date("9999-12-31"), nrow(crosswalk))
  if (!is.null(periods)) crosswalk <- rbind(crosswalk, periods[names(crosswalk)])
  matches$ground_profile_id <- profiles$ground_profile_id
  matches$ground_label <- profiles$ground_label
  matches$country <- NA_character_
  for (i in seq_len(nrow(crosswalk))) {
    rows <- matches$ground_profile_id == crosswalk$ground_profile_id[i] &
      matches$start_date >= crosswalk$valid_from[i] & matches$start_date < crosswalk$valid_until[i]
    if (any(!is.na(matches$country[rows]))) stop("Overlapping ground jurisdiction periods")
    matches$country[rows] <- crosswalk$country[i]
  }
  if (any(!is.na(country) & !is.na(matches$country) & country != matches$country)) {
    stop("Dated jurisdiction disagrees with legacy ground country")
  }
  matches$home_sign <- as.integer(normalize_jurisdiction(matches$team1) == matches$country) -
    as.integer(normalize_jurisdiction(matches$team2) == matches$country)
  matches$context_source <- ifelse(is.na(matches$country), NA_character_, "fairly_random grounds via legacy match")
  if (!is.null(periods)) {
    explicit <- !is.na(matches$country) & matches$ground_profile_id %in% periods$ground_profile_id
    matches$context_source[explicit] <- "audited ground jurisdiction periods"
  }
  list(matches = matches, crosswalk = crosswalk)
}

prepare_model_context <- function() {
  matches <- readr::read_csv("data/build/matches.csv", show_col_types = FALSE)
  legacy <- readr::read_csv("data/cricket_matches.csv", show_col_types = FALSE)
  grounds <- readr::read_csv("data/raw/context/grounds.csv", show_col_types = FALSE)
  periods <- readr::read_csv("data/raw/context/jurisdiction_periods.csv", show_col_types = FALSE)
  profiles <- match_ground_profiles("data/raw")
  joined <- join_match_context(matches, profiles, legacy, grounds, periods)
  dir.create("data/context", recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(joined$matches, "data/context/matches.csv")
  readr::write_csv(joined$crosswalk, "data/context/ground_countries.csv")
  coverage <- aggregate(
    cbind(matches = rep(1L, nrow(matches)), known_country = as.integer(!is.na(joined$matches$country))),
    list(format = matches$format, year = format(matches$start_date, "%Y")), sum
  )
  readr::write_csv(coverage, "data/context/coverage.csv")
  inputs <- c(
    "data/build/matches.csv", "data/cricket_matches.csv", "data/raw/context/grounds.csv",
    "data/raw/context/jurisdiction_periods.csv"
  )
  raw_paths <- list.files("data/raw", pattern = "\\.html\\.gz$", recursive = TRUE, full.names = TRUE)
  inputs <- c(inputs, raw_paths, "R/models/context.R", "R/acquisition.R")
  jsonlite::write_json(
    list(
      inputs = setNames(lapply(inputs, digest::digest, algo = "sha256", file = TRUE), inputs),
      output_sha256 = digest::digest(file = "data/context/matches.csv", algo = "sha256")
    ),
    "data/context/manifest.json",
    auto_unbox = TRUE, pretty = TRUE
  )
  invisible(joined)
}

validate_model_context <- function() {
  manifest <- jsonlite::read_json("data/context/manifest.json", simplifyVector = TRUE)
  for (path in names(manifest$inputs)) {
    if (!file.exists(path) || digest::digest(file = path, algo = "sha256") != manifest$inputs[[path]]) {
      stop("Context input changed; run make model-data: ", path)
    }
  }
  checksum <- digest::digest(file = "data/context/matches.csv", algo = "sha256")
  if (is.null(manifest$output_sha256) || checksum != manifest$output_sha256) {
    stop("Prepared context checksum mismatch; run make model-data")
  }
  invisible(manifest)
}
