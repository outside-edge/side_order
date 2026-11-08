source("R/site.R")
pages <- check_site("out/site")
publication <- read_publication("out/site/out/release/elo")
original <- read_publication("out/release/elo")
stopifnot(identical(publication$manifest, original$manifest))
for (format in c("test", "odi", "t20i")) {
  models <- read_current_publication(file.path("out/site/out/release/models", format))
  original_models <- read_current_publication(file.path("out/release/models", format))
  stopifnot(identical(models$manifest, original_models$manifest))
}
cat("Validated", pages, "pages and publication downloads through", publication$manifest$analysis$as_of, "\n")
