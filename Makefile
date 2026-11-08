.PHONY: sync fetch prepare analyze visualize publish update site lint test check ci-docker model-data models check-models current-models visualize-models publish-models
.PHONY: tune-elo visualize-elo-tuning check-elo-tuning
.PHONY: resolve-model-venues

QUARTO ?= quarto
MODEL_FORMAT ?= Test

sync:
	Rscript -e 'renv::restore(prompt = FALSE)'

fetch prepare analyze visualize publish update:
	Rscript scripts/pipeline.R $@ $(AS_OF) $(FLAGS)

lint:
	Rscript scripts/check.R

test:
	Rscript -e 'testthat::test_dir("tests/testthat", stop_on_failure = TRUE)'

check: lint test

model-data:
	Rscript scripts/models.R prepare

resolve-model-venues:
	Rscript scripts/models.R resolve-venues

models:
	Rscript scripts/models.R compare $(MODEL_ARGS)

tune-elo:
	Rscript scripts/models.R tune-elo $(ELO_FORMAT)

visualize-elo-tuning:
	Rscript scripts/models.R visualize-elo-tuning $(ELO_FORMAT)

check-elo-tuning:
	Rscript scripts/models.R check-elo-tuning $(ELO_FORMAT)

current-models:
	Rscript scripts/models.R current $(MODEL_ARGS)

publish-models:
	Rscript scripts/models.R publish-current $(MODEL_FORMAT)

visualize-models:
	Rscript scripts/models.R visualize-current $(MODEL_FORMAT)

check-models:
	Rscript scripts/check_models.R

site:
	$(QUARTO) render
	Rscript scripts/check_site.R

ci-docker:
	docker run --rm -v "$(CURDIR):/app" -w /app -e RENV_PATHS_LIBRARY=/tmp/library -e RENV_PATHS_CACHE=/tmp/cache rocker/r-ver:4.6.0 sh -c 'apt-get update && apt-get install -y libcurl4-openssl-dev libssl-dev libxml2-dev && make sync check'
