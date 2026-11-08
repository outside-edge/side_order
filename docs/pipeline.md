# Rating pipeline

For current GAM, Stan, Glicko-2, and TrueSkill ratings, see
[current model publication](current_models.md). The weekly workflow updates
those Test, ODI, and T20I ratings alongside Elo; historical model evaluation remains separate.

The R pipeline acquires match results, prepares data, fits ratings, renders figures,
and assembles publications. Each stage can run independently from saved inputs.

See the [README](../README.md) for a quick start and the
[experiment specification](model_experiment.md) for GAM, Stan, and Glicko-2 runs.

## Run

Install R 4.6.0, then run from the repository root:

```sh
make sync
make check
make update
```

`renv.lock` pins the R dependencies. The first R invocation bootstraps `renv`;
`make sync` restores the project library. `make update` acquires missing historical
years, refreshes the current and previous year, and builds a publication through
yesterday. All subsequent analysis and rendering use saved data.

```sh
make fetch
make prepare AS_OF=2025-12-31
make analyze
make visualize
make publish
```

The date belongs to acquisition/preparation. Analysis, figures, and publication
inherit the cutoff from their input manifests. `make publish` requires a recent
cutoff and source receipts. Current and previous-year sources must have been
retrieved after the cutoff day ended in UTC; rerun fetch if preparation advances
the cutoff beyond the cached retrievals. Use the R functions with `require_fresh = FALSE` only
for an explicitly historical local publication. `make update FLAGS=--refresh`
also revisits older source years to incorporate historical corrections.

| Stage | Output | Purpose |
| --- | --- | --- |
| Fetch | `data/raw/<format>/<year>.html.gz` and JSON receipts | Preserve source responses and retrieval metadata |
| Prepare | `data/build/matches.csv`, `manifest.json` | Validate identities, dates, outcomes, coverage, and duplicate agreement |
| Analyze | `out/analysis/<model>/` | Fit each model independently; save ratings, diagnostics, and specification |
| Visualize | `figs/<model>/` | Render saved model outputs without fetching or refitting |
| Publish | `out/release/<model>/` | Assemble verified tables, charts, and provenance |
| Site | `out/site/` | Render the verified publication as a website |

The production adapter writes under `elo/`; experimental comparisons write under
`models/<format>/<origin>/`, with separate model identifiers. They have different
rating scales, fitting periods, covariates, and uncertainty summaries. The shared
match table preserves `drawn`, `tied`, and no-result outcomes separately; its
`score` is a convenient 1/0.5/0 encoding, not a prescribed likelihood for every
model. Additional covariates have their own documented acquisition and joins by
match/team ID. Venue profiles and the audited `fairly_random` mapping supply
ground and country context. The annual results source does not supply toss or
umpire covariates.

## Data

The source is ESPNcricinfo's annual [match-results tables](https://stats.espncricinfo.com/ci/engine/records/team/match_results.html?class=1;id=2025;type=year).
Collection starts in 1877 for Tests, 1971 for ODIs, and 2005 for T20Is. Coverage is
the set of matches listed there; it has not been independently certified as a census.

Each receipt records the requested URL, retrieval time in UTC, SHA-256 of the
uncompressed response, format, year, and row count. `httr2` provides HTTP retries
and throttling, including `Retry-After`; `rvest` and `xml2` parse saved pages.
Verified historical downloads are reused. A stopped download can resume.

Missing years, unexpected tables, unknown outcomes, invalid winners, pagination,
conflicting duplicate IDs, and checksum failures stop preparation. An explicit
“No records found” response is required for an empty year. Cross-year matches
are deduplicated only when their records agree. A refreshed page that drops a
previously recorded match stops before overwriting that page.

Matches retain both start and completion dates. Only completed matches through
the requested cutoff enter analysis. Stable team IDs connect name changes.
No-result matches remain in the shared table, with a missing score.
Team IDs are the identifiers in these tables' team-profile links. Some differ
from the old scraper's API IDs, notably invitational teams. Join older covariates
by match ID and reconcile participant identities before combining team IDs across
the two sources.

## Elo specification

The implementation calls the documented `EloRating::e.single()` update function,
the same function used internally by `elo.seq()`. It uses an initial rating of
1,000, normal-CDF expectation, and integer rounding after every match. K is
selected separately for each format as described below. The fixed K=100
baseline still matches all 100 final team ratings in the recorded 2025 Test/T20I
fixtures against an independent `elo.seq()` reference.

The normal-CDF probability is
`Φ((rating1 − rating2) / (200 × √2))`. This is distinct from the logistic link in
Bradley–Terry. A logistic variant should have a separate specification and
numerical checks. These parameter choices are a baseline, not a claim of optimal
predictive performance.

- Wins score 1 and losses 0. Draws and ties score 0.5 each. Matches recorded as
  tied are treated as ties even if a bowl-out or Super Over subsequently decided
  a winner.
- Abandoned, cancelled, and no-result matches cause no rating update.
- Each format has a separate pool. Results are ordered by completion date,
  start date, and match ID. The latter is a reproducible convention for same-day
  finishes, not a claim about their exact finish times.
- Month-end ratings use the last completed update on or before each calendar
  month end. There is no interpolation, future-day averaging, or inclusion of
  teams before their first rated match.
- Current rankings include teams with a rated match within 730 days. Inactive
  teams remain in the CSV without a current rank. Fewer than ten rated matches
  is marked provisional; equal ratings share a competition rank. These are our
  display rules, not ICC eligibility rules.

The update ledger records both teams' ratings before and after every rated match.
Charts show end-of-day match updates for the current top ten active teams, without
smoothing. Recent-history comparisons cover the current and preceding nine calendar
years, with team names and current ratings at the line ends. Full histories appear
in separate team panels with common axes. PNG and SVG versions are published.
The same team uses the same color and line type across formats within a publication.
Histories are reconstructed from the saved source version; they are
not evidence of what could have been published using records available at the time.
Git history preserves successive actual publications.

Elo currently has no venue or margin adjustment, inactivity decay, or standard
errors. Glickman uncertainty and Stan posterior summaries belong to their own
models and should not be presented as interchangeable Elo standard errors.
Before comparing methods, use common chronological forecast cutoffs and document
each model's treatment of draws, ties, inactivity, and missing covariates.
The [modeling proposal](rating_models.md) sets out institutional versus lineup
strength, TrueSkill-style and GAM extensions, venue context, and the distinction
between live ratings and retrospective smoothing.

## Selecting K

`make analyze` and the scheduled `make update` select K before producing ratings.
For each format, the selection origin is January 1 of the publication year.
Selection is recomputed from the saved source version; corrections to prior
years can therefore change K within the publication year.
Candidates are the integers 1–200 and 220–400 by 20. Each candidate replays all
history completed before the origin, starting every team at 1,000. The selected
K minimizes mean squared expected-score error on matches starting in the prior
five complete calendar years and completed before the origin. Exact ties prefer
the smaller K. Selection requires at least 100 matches and representation in
every tuning year; insufficient data stop publication rather than silently
substituting K=100. At K=1, integer rounding prevents learning from equal starts.

Forecasts use ratings from results completed strictly before each match starts.
Same-day results are unavailable because completion times are not recorded.
A Test spanning New Year belongs to its starting year and cannot enter January
selection until its result exists. Draws and ties score 0.5; no-results are excluded.
Squared error targets the conditional mean score, not a three-category outcome
probability. The model retains the full production team universe, including
associates and historical invitational sides.

After selection, the entire history is replayed at the selected K through the
publication cutoff. These retrospective curves do not splice annual K values or
represent historical live forecasts. All rating CSVs include K; `k_selection.csv`
records the selection period and sample, and `k_tuning.csv` records every candidate
loss. Both files are included in the publication and its checksum manifest.

The separate evaluation workflow selects K at annual origins from 2015 onward
and evaluates the following year's forecasts while updating ratings between
matches. Five years is the primary tuning window, with three- and ten-year
sensitivities. It compares against fixed K=100 and a constant expected score of
0.5, using equal match weights and identical supported evaluation matches.
The final evaluation year can be partial. Results previously inspected during
development, including recent ODI outcomes, make this a retrospective assessment,
not blinded confirmation. The current K is selected using only complete prior
years regardless of what has been observed during development.

```sh
make tune-elo
make check-elo-tuning
make visualize-elo-tuning
```

These commands use the existing `scripts/models.R` runner and can be restricted
with `ELO_FORMAT=ODI`. Analysis functions live in `R/models/elo_tuning.R`, plotting
in `R/models/elo_tuning_plots.R`, and tests in `tests/testthat/test-elo-tuning.R`.
Results live in `out/analysis/elo_tuning/<format>/`; figures in
`figs/elo_tuning/<format>/`. Saved outputs include compressed candidate forecasts,
annual tuning curves and evaluation predictions, match-weighted summaries,
current selections, leave-one-year-out stability, and every candidate's ratings.
The checker reconstructs scores and choices from saved forecasts and rejects
missing or duplicated candidates and evaluation rows. Successful runs replace
outputs atomically; failed diagnostics are retained in ignored `failed-*` folders.

Candidates within 0.001 MSE of the current minimum are flagged as a descriptive
sensitivity set, not a confidence interval. Annual results are dependent through
series and teams; the reports show paired annual differences without pretending
matches are independent. The historical gain was small for T20Is. Neither a
precise grid minimum nor a retrospective gain establishes future superiority.
Venue, lineup, margin and inactivity adjustments remain separate model changes.

## Publication and checks

The workflow is scheduled for Monday at 06:17 UTC, with monthly snapshots included
in each update. Scheduling starts when the workflow is on the default branch.
It runs `make check`, updates all stages, and renders and checks the website before
committing the data/output directories. GitHub schedules can be delayed or disabled;
the publication manifest records the actual cutoff. After committing an update,
the workflow passes that commit to the Pages workflow, which renders and deploys
the corresponding website. Merges to `main` also rebuild the site.

The website uses [Quarto 1.10.19](https://quarto.org/docs/get-started/).
Its source is `index.qmd`, `docs/`, and `_quarto.yml`; compiled HTML stays in the
ignored `out/site/` directory. To build and check it locally:

```sh
make site
```

Rendering verifies and reads `out/release/elo/` without fetching or fitting.
The site check validates local page and asset links and verifies the copied
downloads against the original publication manifest. CI renders all eight pages.
GitHub Pages uses the Actions publishing source and the `github-pages` environment.

Every stage writes to a temporary directory before replacing its previous output.
Input/output hashes prevent mixing different data, model, or figure versions.
Publication also requires every stage's code hashes to match the current pipeline R code
and dependency lockfile. Rebuild preparation, analysis, and figures after changing that code.
The website reader in `R/site.R` is excluded from model-stage fingerprints.
A failed stage leaves the previous publication intact. If interrupted between
directory renames, recover `<output>.previous` before rerunning; the pipeline
refuses to discard that recovery directory automatically.

```sh
make check
make ci-docker
```

`make check` runs `lintr` and `testthat` against the maintained pipeline, including
real source fixtures, the legacy BOM and outcome regressions, exact numerical
reference checks, absence of future-data effects, and publication failure cases.
`make ci-docker` uses the standard `rocker/r-ver:4.6.0` image and requires a running
Docker daemon. It checks the R pipeline; run `make site` separately with Quarto
to check the website. The GitHub checks run both on Ubuntu.

## Research and historical outputs

The superseded parser, preparation script, Elo driver, and Elo outputs are
available in Git history. The original inputs, `scripts/glickman.R`, and
`scripts/stan/` remain for continued model development. The Glickman and Stan
scripts are outside the scheduled pipeline and its dependency environment; see
the [audit](correctness.md) for known defects and unresolved reproduction
differences. The legacy importer in `scripts/prepare_matches.R` fixes BOM handling
and outcome coding for checks against the old data.
