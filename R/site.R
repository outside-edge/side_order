read_publication <- function(directory) {
  manifest <- jsonlite::read_json(file.path(directory, "manifest.json"))
  files <- names(manifest$files)
  required <- c("latest.csv", "monthly.csv", "updates.csv")
  if (!all(required %in% files) || any(basename(files) != files) || anyDuplicated(files)) {
    stop("Invalid publication file manifest")
  }
  for (name in files) {
    path <- file.path(directory, name)
    if (!file.exists(path) || !identical(digest::digest(file = path, algo = "sha256"), manifest$files[[name]])) {
      stop("Publication checksum mismatch: ", name)
    }
  }
  latest <- readr::read_csv(
    file.path(directory, "latest.csv"), show_col_types = FALSE,
    col_types = readr::cols(date = readr::col_date(), last_rated_match = readr::col_date())
  )
  if (
    !nrow(latest) || anyNA(latest$date) ||
      !identical(unique(as.character(latest$date)), manifest$analysis$as_of) ||
      !identical(manifest$source$as_of, manifest$analysis$as_of)
  ) {
    stop("Inconsistent publication cutoff")
  }
  k <- manifest$analysis$specification$k
  if (!is.list(k) || !setequal(names(k), unique(latest$format)) || !"k" %in% names(latest) ||
        anyNA(latest$k) || any(latest$k != unlist(k[latest$format], use.names = FALSE))) {
    stop("Inconsistent publication K values")
  }
  if (!is.null(manifest$analysis$specification$k_selection) &&
        !all(c("k_selection.csv", "k_tuning.csv") %in% files)) stop("Missing K-selection evidence")
  list(manifest = manifest, latest = latest)
}

read_current_publication <- function(directory) {
  manifest <- jsonlite::read_json(file.path(directory, "manifest.json"))
  models <- c("gam", "stan_dynamic_probit", "glicko2", "trueskill")
  required <- c("latest.csv", "coverage.csv", "strengths.csv", "stan_diagnostics.json",
    as.vector(outer(models, c(".png", ".svg"), paste0))
  )
  if (!isTRUE(manifest$stan_diagnostics_passed) || !all(required %in% names(manifest$files))) {
    stop("Invalid current model publication")
  }
  for (name in names(manifest$files)) {
    if (basename(name) != name || !file.exists(file.path(directory, name))) stop("Missing model file: ", name)
    if (!identical(digest::digest(file = file.path(directory, name), algo = "sha256"), manifest$files[[name]])) {
      stop("Current publication checksum mismatch: ", name)
    }
  }
  latest <- readr::read_csv(file.path(directory, "latest.csv"), show_col_types = FALSE)
  if (!setequal(unique(latest$model), models) || anyNA(latest$as_of) ||
        !identical(unique(as.character(latest$as_of)), manifest$as_of)) {
    stop("Inconsistent current publication models or cutoff")
  }
  if (anyDuplicated(latest[c("model", "team_id")])) stop("Duplicate current team ratings")
  list(manifest = manifest, latest = latest)
}

site_model_ratings <- function(publication, model) {
  rows <- publication$latest[publication$latest$model == model, ]
  if (!nrow(rows)) stop("Missing current model: ", model)
  rows <- rows[order(!rows$is_active, -rows$estimate, rows$team_id), ]
  data.frame(
    Rank = ifelse(rows$is_active, rows$rank, "Inactive"),
    Team = paste0(rows$team, ifelse(rows$is_provisional, " (provisional)", "")),
    Strength = sprintf("%.2f", rows$estimate),
    `90% interval` = sprintf("%.2f to %.2f", rows$lower, rows$upper),
    `Last match` = rows$last_rated_match, check.names = FALSE
  )
}

site_ratings <- function(publication, format) {
  rows <- publication$latest
  if (!format %in% rows$format) stop("Missing publication format: ", format)
  rows <- rows[rows$format == format & rows$is_active, ]
  rows <- rows[order(-rows$rating, rows$team_id), ]
  data.frame(
    Rank = rows$rank, Team = paste0(rows$team, ifelse(rows$is_provisional, " (provisional)", "")),
    Elo = rows$rating, `Rated matches` = rows$rated_matches,
    `Last rated match` = rows$last_rated_match, check.names = FALSE
  )
}

check_site <- function(directory, base_path = "/side_order/") {
  directory <- normalizePath(directory, mustWork = TRUE)
  pages <- list.files(directory, pattern = "[.]html$", recursive = TRUE, full.names = TRUE)
  if (!file.exists(file.path(directory, "index.html"))) stop("Missing site index")
  for (page in pages) {
    html <- xml2::read_html(page)
    nodes <- xml2::xml_find_all(html, "//*[@href or @src]")
    urls <- unique(c(xml2::xml_attr(nodes, "href"), xml2::xml_attr(nodes, "src")))
    urls <- urls[!is.na(urls) & nzchar(urls)]
    urls <- urls[!grepl("^([a-zA-Z][a-zA-Z0-9+.-]*:|//)", urls)]
    for (url in urls) {
      path <- utils::URLdecode(sub("[?#].*$", "", url))
      if (!nzchar(path)) next
      if (startsWith(path, "/")) {
        if (!startsWith(path, base_path)) stop("Link outside site base path: ", url)
        target <- file.path(directory, substring(path, nchar(base_path) + 1L))
      } else {
        target <- file.path(dirname(page), path)
      }
      if (dir.exists(target)) target <- file.path(target, "index.html")
      if (!file.exists(target)) stop("Broken site link in ", basename(page), ": ", url)
      target <- normalizePath(target, mustWork = TRUE)
      if (!startsWith(target, paste0(directory, "/"))) stop("Link escapes site: ", url)
    }
  }
  invisible(length(pages))
}
