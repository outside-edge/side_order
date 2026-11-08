# Contextual ratings experiment

This is an exploratory, retrospective comparison. Historical results have already
been inspected for the Elo pipeline; these are not blinded or preregistered tests.
The target is the distribution of a national side's loss, draw/tie, and win in a
match, given information available before its start. Each match receives equal
weight. Formats are fitted separately. No-results are excluded, never losses.
The national-team experiment excludes ICC World XI, World-XI, Asia XI and Africa XI.

## Initial specification

Start with Tests from 2000 onward, and a frozen forecast origin of 2024-01-01,
evaluating matches starting in 2024. This is an implementation experiment, not
enough evidence to select a production winner. The command accepts other origins
and formats for subsequent rolling evaluations. Training requires completion
strictly before the origin; an ongoing Test cannot contribute its result.

* **GAM:** mgcv penalized factor-smooth team trajectories, evaluated as the
  difference of the same function for the two opponents. Ordered-logistic
  outcomes with symmetric draw thresholds; a small threshold grid is selected
  on the final training year, then the model is refitted. REML selects smoothing
  penalties within each training fit. Home advantage has a global coefficient
  and penalized country/ground deviations. Forecast strengths are held at the
  last training date, avoiding unconstrained spline extrapolation. These are
  plug-in probabilities; parameter uncertainty is shown separately in the
  approximate strength intervals, not integrated into match probabilities.
* **Stan:** a team-level TrueSkill-style ordinal-probit model with quarterly
  Gaussian random-walk strengths, a fixed performance-difference variance of
  one, and symmetric draw thresholds. Home advantage and draw propensity have
  partially pooled country and ground effects. Log draw margin also has a linear
  calendar-time trend. Calendar quarters with no games
  still increase process uncertainty. This is a batch Bayesian extension, not
  the original TrueSkill message-passing algorithm or a player-rating model.
* **Glicko-2:** PlayerRatings, calendar-month periods, including empty periods,
  default volatility and rating-deviation settings documented in the output.
  This is an uncertainty-aware comparator without contextual covariates.
* **Elo:** the original normal-CDF, K=100, integer-rounded baseline. The current
  publication now selects K by format; this saved pilot retains its original baseline.
  Neither Elo nor Glicko's expected score is a three-category probability.
  Their rating differences receive an ordered-logistic calibration trained on
  earlier out-of-period predictions, with a symmetric fixed-threshold grid.
  Calibration uses the most recent 1,825 days, selecting the threshold on the
  final training year. Historical predictions are frozen for the same number
  of months as the evaluation horizon. For the annual pilot, these are January
  vintages, not predictions updated within each year. Both unadjusted and
  home-adjusted calibrations are retained, so a contextual model's apparent
  improvement is not simply its access to home advantage.
* **Climatology:** training draw frequency, equal probabilities of either side
  winning the remaining mass, with a one-count prior per outcome. Include both
  full-history and recent-window versions, plus recent home-conditioned
  frequencies. At neutral venues, loss and win probabilities are constrained
  equal. The home-conditioned baseline uses a one-count prior per category.

All directional predictors change sign when the opponents are exchanged. A
ground intercept cannot favor an arbitrary first-listed team. Draw thresholds
are invariant to this exchange. Team trajectories have penalized/proper-prior
location identification; reported strengths are centered across fitted teams.
Absolute improvements shared by all teams are not identified. Glicko updates
are simultaneous within completion month; a March 1 result first enters the
April vintage. This sacrifices within-month information but never uses it early.
Historical calibrations and holdout forecasts use the same period convention.

Stan starts each team's uncentered strength with a standard-normal prior and
uses quarterly innovations with scale `sigma_walk ~ half_normal(0, 0.3)`.
Centering each quarter removes a common level while leaving pairwise differences
unchanged. A late-entering team evolves from the common 2000 start, so its debut
prior is more diffuse; estimating a separate entry-state model is future work.
Home's global prior is `normal(0, 0.75)`, country/ground home scales have
`half_normal(0, 0.3)` priors, and draw-effect scales have `half_normal(0, 0.5)`
priors. The log draw margin starts with `normal(log(0.3), 1)` for Tests (0.01 for
limited overs); its per-year trend has `normal(0, 0.05)` prior. Country and ground
effects are descriptive, partially pooled deviations; their decomposition can
remain uncertain when grounds are nested within a country.

## Context and missingness

The saved annual results pages provide match and ground profile IDs. The legacy
match table supplies full ground names. The sibling fairly_random ground table
maps those names to cricket jurisdictions (including England and West Indies).
Mappings are accepted only after participant checks and unique country checks;
conflicting mappings fail. Dated overrides handle Dhaka's Pakistan/Bangladesh
jurisdiction change, leaving the 1971 war interval unassigned. No source matches
fall in that interval. Legacy and current ground-ID namespaces are not joined.
The imported mapping and source hash are recorded in this repository.

| Added column | Definition |
| --- | --- |
| `ground_profile_id` | Integer ID from the ground profile link in the saved annual results page; not the legacy ground ID |
| `ground_label` | Short ground label in that results page |
| `country` | Audited cricket jurisdiction at the match date; missing if unmapped |
| `home_sign` | +1 for team 1 geographically at home, -1 for team 2, 0 for a known neutral venue, missing for unknown jurisdiction |
| `context_source` | Mapping provenance label; missing when no country was resolved |

Geographic home status is +1 for team 1 at home, -1 for team 2, and zero at a
known neutral ground. Unmapped countries remain missing. The contextual comparison
uses known-country matches, with coverage reported. Overseas nominal home games
are geographically neutral. New grounds/countries use the population-level
effect; Stan integrates their random-effect uncertainty. The GAM requires teams
seen in training, so the shared comparison excludes new-team holdout matches
and reports that count explicitly. This first comparison therefore evaluates
established national teams. Prior-predictive evaluation of new teams is future work.

Coverage is a selection constraint, not a missing-at-random claim. The 2024 Test
experiment has complete venue coverage. T20I coverage is substantially worse:
many recent venues are absent from the legacy mapping. The command can fit
other formats, but their results describe the mapped subset; do not call them
all-international ratings without extending acquisition and missing-context handling.

Toss, batting order, and umpire fields in the historical table have incomplete
recent coverage. They are reserved for a separately defined post-toss prediction
experiment. Realized rain, DLS use, winning margin, and match duration cannot be
pre-match regressors. No player-lineup or causal interpretation is claimed.

## Checks and reporting

Use the same eligible holdout matches for every model. Save each match's three
probabilities and outcome, origin, model, and input/code fingerprints. Report
multiclass log loss, Brier score (sum over three categories), classwise calibration,
and accuracy as a secondary measure (equal credit among tied maximum probabilities).
One year's
scores are descriptive: series dependence makes an independent-match standard
error inappropriate. Do not declare a winner from this pilot or rank its tiny
subgroups. There are only three draws in the 2024 Test evaluation; draw-calibration
bins are descriptive counts, not a precise calibration assessment.

Test swapped-team invariance, probability normalization, no-result exclusion,
ongoing-match exclusion, context joins, unseen-level behavior, elapsed-time
uncertainty, and simulation recovery. Run four Stan chains; inspect divergences,
treedepth, R-hat and bulk/tail ESS, plus posterior-predictive outcome frequencies.
Retrospective curves and filtered forecasts are labeled separately. Future
quarterly origins must rerun fits using only completed training matches; the
full-data smoother is never used to reconstruct historical forecasts.

## Run and inspect

Restore the R dependencies with `make sync`. Install CmdStan 2.40.0 once:

```sh
Rscript -e 'dir.create("renv/local/cmdstan", recursive=TRUE, showWarnings=FALSE); cmdstanr::install_cmdstan(dir="renv/local/cmdstan", version="2.40.0", cores=2)'
make model-data
make check
make check-models
make models MODEL_ARGS='Test 2024-01-01 2025-01-01 1000'
Rscript scripts/models.R visualize out/analysis/models/test/2024-01-01
```

`CMDSTAN` can select an existing installation. The default uses the local pinned
installation. `make check-models` runs four-chain simulation recovery and actual
Stan generated-quantities swap tests. `make check` runs the fast R tests and lint.
The final numeric argument is warmup and retained draws **per chain**, with four
chains. The default is 1,000 of each. Model origins and window ends must be month
boundaries, with horizons of one to twelve months. Analysis fails if context
inputs changed without preparation or Stan diagnostics fail. A comparison is
replaced only after a complete successful run.
Failed fits remain in ignored `failed-*` directories beside the comparison so
their draws and diagnostics can be inspected. Successful figure rendering also
replaces the previous figure set together.

Prepared context lives in `data/context/`; the copied source mapping is in
`data/raw/context/`. Model output lives in `out/analysis/models/<format>/<origin>/`,
including `predictions.csv`, `metrics.csv`, `calibration.csv`, tuning scores,
`strengths.csv`, posterior diagnostics and a hash manifest. MCMC draws and fit
objects are ignored build products. Figures are rendered separately into
`figs/models/<format>/<origin>/`. These evaluation runs are not scheduled.
[Current ratings](current_models.md) have separate fitting and publication commands.

Strength CSVs distinguish retrospective trajectories from forecasts and retain
each model's scale. GAM intervals are approximate normal 90% intervals, including
smoothing-parameter uncertainty where supplied by mgcv; Stan intervals are 90%
posterior intervals. Neither is an interval for the result of an individual match.

## References and scope

The exact Lewis spline roll-call reference remains unresolved. The implemented
GAM uses the documented mgcv paired linear-functional construction and is not
represented as a replication of Lewis's model.

Implementation references: [mgcv linear functionals](https://stat.ethz.ch/R-manual/R-devel/library/mgcv/html/linear.functional.terms.html),
[mgcv ordinal likelihood](https://stat.ethz.ch/R-manual/R-devel/library/mgcv/html/ocat.html),
[PlayerRatings manual](https://cran.r-project.org/web/packages/PlayerRatings/PlayerRatings.pdf),
[Glickman's Glicko-2 specification](https://glicko.net/glicko/glicko2.pdf),
[Stan ordered probit](https://mc-stan.org/docs/functions-reference/bounded_discrete_distributions.html#ordered-probit-distribution),
and [TrueSkill](https://www.microsoft.com/en-us/research/wp-content/uploads/2006/01/TR-2006-80.pdf).
