# Current ratings from other models

Current ratings describe national teams using completed matches available through
an explicit data cutoff. They are separate from forecast evaluation: a current fit
uses all eligible observations through that cutoff and needs no held-out matches.
Each format has its own fit. Publications cover Tests, ODIs, and T20Is from 2000 onward.
No-results and invitational XIs are excluded. Unknown venue countries stop the
publication rather than silently removing matches from contextual models.

Four methods are published separately:

- GAM: the existing paired team splines, with country and ground home effects.
  The final-year internal validation chooses the draw threshold; all eligible
  data then enter the fit. Current strength is the fitted boundary value and
  its approximate 90% interval, including smoothing uncertainty.
- Stan: the existing dynamic TrueSkill-style ordinal-probit model, with quarterly
  strengths and contextual home/draw effects. The current quarter's posterior
  mean and 90% interval describe latent strength. Four-chain sampling diagnostics
  must pass before publication. Empty quarters increase uncertainty.
- Glicko-2: `PlayerRatings` with calendar-month completion periods. The current
  month's results enter a partial period rebuilt from scratch at each update;
  they are never applied twice. Ratings are accompanied by rating deviations
  and approximate normal 90% intervals. Inactivity inflates rating deviation
  for elapsed empty periods, capped at 350.
- TrueSkill: the forward filtering algorithm in `TrueSkillThroughTime` 1.0.0.
  Each national side is one competitor. Match completion dates supply timestamps
  in days; initial mean is 0, initial standard deviation 6, performance standard
  deviation 1, and dynamic standard deviation 0.03 per square-root day. Draw
  probability is the fitted sample's draw/tie frequency with a Beta(1,1) adjustment.
  These are baseline settings, not tuned claims of optimal prediction. The
  backward smoothing procedure is not called. No venue effects are included.

Higher estimates mean stronger teams within a method. The methods' scales differ
and should not be averaged. Rankings use point estimates among teams with a
rated match in the preceding 730 days; fewer than ten matches is provisional.
Rankings do not measure the probability that one team is better than another.
Intervals describe model-based uncertainty about strength, not match outcomes.

All outputs record their cutoff, training IDs, coverage, model settings, package
versions, and input/code hashes. Historical curves from a full GAM or Stan fit
are retrospective. TrueSkill's draw setting uses the full fitted sample, so its
saved historical filtering curves also must not be treated as archived forecasts.
Git history preserves actual successive publications. Changing settings or
selecting methods by performance belongs in the separate evaluation pipeline.

Implementation references: [TrueSkillThroughTime manual](https://cran.r-project.org/web/packages/TrueSkillThroughTime/TrueSkillThroughTime.pdf)
and [contextual model specification](model_experiment.md).

## Run and publish

Restore the pinned R dependencies with `make sync` and install CmdStan as described
in the [experiment specification](model_experiment.md#run-and-inspect). Then:

```sh
make update
make model-data
make resolve-model-venues
make current-models MODEL_ARGS='ODI 1000'
make visualize-models MODEL_FORMAT=ODI
make publish-models MODEL_FORMAT=ODI
make site
```

`make update` acquires and prepares the latest match data and updates Elo. The
current-model fit inherits the prepared cutoff; it does not fetch data or run a
holdout evaluation. `MODEL_ARGS='Test 1000'` specifies the format and warmup and
retained iterations per chain; four chains run. Use `ODI` for one-day internationals.
Use `T20I 2000` for Twenty20 internationals, which use 2,000 warmup and retained
iterations per chain. All three formats require complete venue
coverage after the separate resolution step.

If only Stan diagnostics fail, retain the completed GAM rather than repeating its
validation and full fit. Set `GAM_FIT` to the retained run's `fits.rds` path, then:

```sh
make current-models MODEL_ARGS="T20I 2000 $GAM_FIT"
```

The optional saved-fit argument explicitly reuses that GAM and its selected
threshold. It verifies convergence, the tuning grid, and every row of the GAM's
responses and predictors against the current sample. Changes to those inputs are
rejected. Use this only to increase sampling with the same raw sample, data
cutoff, and GAM specification. The manifest records the reused artifact and its SHA-256;
Glicko-2, TrueSkill, and Stan are recomputed. Omitting the saved-fit argument
reproduces the entire analysis from source data.

The initial T20I run had no divergences and passed R-hat checks, but its
random-walk scale had bulk effective sample size 381 against the required 400.
The longer run increases Monte Carlo precision without changing the model or
relaxing publication diagnostics.

Analysis writes to `out/analysis/current/<format>/`, charts to
`figs/models/current/<format>/`, and publication to `out/release/models/<format>/`,
where the format directory is lowercase.
The site reads the saved publication and verifies its hashes. Failed fits preserve
the previous output and retain their diagnostic files. The weekly ratings workflow
runs these stages for Tests, ODIs, and T20Is after the Elo update. A failed model
update retains that format's previous publication while Elo can still update.
The model page flags any difference between their cutoffs. Historical evaluation
remains `make models`.

## Venue additions

`make model-data` preserves the original legacy-based country join in
`data/context/matches.csv`. The separate `make resolve-model-venues` step reads
that table and the pinned snapshot in `data/raw/context/ground_bridge/grounds.csv`,
then writes `data/context/resolved/matches.csv`, `coverage.csv`, `venue_audit.csv`, and a
checksum manifest. Current models read this resolved stage. The historical
evaluation continues to use its original context stage.

The resolution is a deterministic lookup of verified locations, not a statistical
prediction based on teams or outcomes. The reference key is the ESPN ground
profile ID and a validity interval, with inclusive `valid_from` and exclusive
`valid_until`. Newly verified locations begin at the earliest observed match
covered by the audit; legacy links use open historical intervals. These are not
stadium opening dates. Country means cricket jurisdiction, so
Scotland and West Indies retain their cricket identities. Location labels are
evidence for the country assignment and do not resolve disagreements over a
stadium's exact name. Each row records a source URL and a method:
`verified_location` for researched locations, `legacy_match_link` for exact historical match anchors, or
`audited_jurisdiction` for the previously reviewed jurisdiction periods. Reference
IDs are distinct from the old ground table's IDs.

The left-hand universe is every original context match, keyed by `match_id`.
The join is many matches to at most one dated mapping. Duplicate match IDs,
overlapping mapping intervals, missing evidence, and conflicts with known
countries stop the step. All original match IDs, rows, and outcomes are preserved.
Only missing countries are filled; home status is recomputed from the resolved
jurisdiction. Unresolved countries remain missing, distinct from neutral venues.

| Added field | Meaning |
| --- | --- |
| `country_original` | Country before resolution; empty means unresolved by the legacy join |
| `home_sign_original` | Original home indicator, including missing values |
| `venue_resolution` | `existing`, the bridge method used for a filled country, or `unresolved` |
| `venue_source` | Evidence URL for a filled country; empty for unchanged rows |

`home_sign` remains 1 for team 1 at home, -1 for team 2 at home, 0 for a known
neutral jurisdiction, and missing for an unknown jurisdiction. The audit contains
one row per eligible match originally lacking a country, with original and
resolved values and the legacy-link failure reason. Coverage reports eligible,
originally known, resolved, and unresolved counts separately for each format.
An eligible match starts in 2000 or later, has a completed scored result within
the prepared cutoff, and involves national teams rather than invitational XIs.
The published model output includes the format's resolved-match audit.

The canonical dataset is maintained independently in
[`outside-edge/cricket_grounds`](https://github.com/outside-edge/cricket_grounds).
Its 357 dated rows cover 356 ESPN ground profile IDs. It includes the existing
legacy links and audited periods as well as the newly researched venues. The
snapshot manifest records its immutable Git commit, download URL, and SHA-256.
Reads verify the checksum; updates validate the schema and date intervals before
replacing the cached snapshot. Supply a full commit SHA when adopting a reviewed
revision. For example, to fetch the initial revision:

```sh
make fetch-model-venues GROUNDS_REF=71e87e46cba64eda4668bb0bc0a1667c6a22ca12
make resolve-model-venues
```

At the 2026-10-25 cutoff, the resolution step fills all 60 originally missing ODI
countries and all 1,360 originally missing T20I countries. All 3,377 eligible ODIs
and 4,113 eligible T20Is are retained, with zero unresolved venues. The first ten
ODI mappings also covered 97 T20Is; the remaining 1,263 T20Is required 83 further
profile-level mappings. No matches were dropped to obtain complete coverage.

Team IDs remain the identity keys. Current tables use each team's latest observed
name, so Swaziland and Eswatini appear as one team. The country comparison also
recognizes that rename when assigning home status; historical source names remain
unchanged.

### T20I upstream diagnosis

The upstream [`fairly_random` ground table](https://github.com/outside-edge/fairly_random/blob/0ed74ecb4f193b4225e9801a9a8cdbe753b82861/data/grounds.csv)
has 1,912 rows and is byte-identical to our cached copy. Its default branch was
checked on 2026-11-08 and still points to commit `0ed74ec` from 2023-10-23.
Refreshing that upstream snapshot would therefore add no venue records.

Our existing crosswalk learns current ground profile IDs through shared legacy
match IDs and full ground names. Of the 1,360 originally unmapped eligible T20Is,
1,335 have no legacy match anchor. The other 25 have legacy ground names without
matching country records: Pierre Werner Cricket Ground, National Sports Academy
in Sofia, Scott Page Field in Vinor, and Bayer Uerdingen Cricket Ground. The gaps
start in 2020 and grow as newer venues enter the international schedule. They
reflect the historical snapshot and crosswalk coverage; they are not missing
match outcomes. The generated [venue audit](../data/context/resolved/venue_audit.csv) exposes both failure reasons
and the affected profile IDs for a source-level refresh.
Some location labels still occur in the old ground table but cannot be linked
without a current profile ID. Name-only imputation would be unsafe: the upstream
table associates `Doha` with both Kuwait and Qatar, and `St Saviour` with both
England and Jersey. The new grounds bridge supplies the verified profile-level
links and new venue records needed to resolve these gaps. It does not use a blanket city-name match.

The current Test sample adds two audited ground mappings missing from the older
`fairly_random` map: New Chandigarh to India, and Tarouba to the West Indies
cricket jurisdiction. Ground profile IDs come from the saved match-result pages.
The [Punjab Cricket Association](https://cricketpunjab.in/pdf/Terms-condition--2024444.pdf)
identifies the New Chandigarh venue; [Cricket West Indies](https://www.windiescricket.com/news/cpl-venue-preview-brian-lara-cricket-academy/)
locates the Brian Lara venue in Tarouba, Trinidad. Sources and validity periods
are recorded in `data/raw/context/jurisdiction_periods.csv`.
