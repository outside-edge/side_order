# T20I Elo K selection through 2026-10-25

Primary policy: select K each January using the preceding 5 complete years.
Current selection: **K = 77**, using cutoff 2026-01-01 and 2477 tuning matches.

Across 3714 evaluation matches in 12 years, mean squared error was 0.21362 versus 0.21452 at K = 100.
The selected policy did better in 8 of 12 evaluation years (0 exact ties).

These are retrospective forecasts with chronological separation, not blinded confirmation.
Squared error measures expected-score accuracy, not three-outcome probability accuracy.
The production pipeline uses the same five-year selection rule.

## Evaluation and tuning-window sensitivity

|scope     | window|    n| years| first_year| last_year| tuned_mse| baseline_mse| neutral_mse| difference| years_better| years_equal|
|:---------|------:|----:|-----:|----------:|---------:|---------:|------------:|-----------:|----------:|------------:|-----------:|
|available |      3| 3714|    12|       2015|      2026|   0.21371|      0.21452|     0.24731|   -0.00081|            9|           0|
|available |      5| 3714|    12|       2015|      2026|   0.21362|      0.21452|     0.24731|   -0.00091|            8|           0|
|available |     10| 3714|    12|       2015|      2026|   0.21428|      0.21452|     0.24731|   -0.00024|            7|           0|
|common    |      3| 3714|    12|       2015|      2026|   0.21371|      0.21452|     0.24731|   -0.00081|            9|           0|
|common    |      5| 3714|    12|       2015|      2026|   0.21362|      0.21452|     0.24731|   -0.00091|            8|           0|
|common    |     10| 3714|    12|       2015|      2026|   0.21428|      0.21452|     0.24731|   -0.00024|            7|           0|

Available rows use each policy's supported folds; common rows use their intersection.
The final year can be partial. Each match has equal weight; annual differences are dependent.

## Annual primary evaluation

| year|supported | selected_k| n_tuning| n_evaluation|partial_year | tuned_mse| baseline_mse|
|----:|:---------|----------:|--------:|------------:|:------------|---------:|------------:|
| 2015|TRUE      |         21|      279|           59|FALSE        |   0.24023|      0.26231|
| 2016|TRUE      |         15|      271|           97|FALSE        |   0.24497|      0.24523|
| 2017|TRUE      |         15|      347|           63|FALSE        |   0.22444|      0.23400|
| 2018|TRUE      |         21|      331|           78|FALSE        |   0.18406|      0.18790|
| 2019|TRUE      |         28|      357|          299|FALSE        |   0.24832|      0.24997|
| 2020|TRUE      |         28|      596|           90|FALSE        |   0.21666|      0.24010|
| 2021|TRUE      |         30|      627|          328|FALSE        |   0.23141|      0.23529|
| 2022|TRUE      |         30|      858|          513|FALSE        |   0.22115|      0.21805|
| 2023|TRUE      |         52|     1308|          435|FALSE        |   0.22469|      0.22400|
| 2024|TRUE      |         60|     1665|          646|FALSE        |   0.20668|      0.20611|
| 2025|TRUE      |         69|     2012|          555|FALSE        |   0.19799|      0.19825|
| 2026|TRUE      |         77|     2477|          551|TRUE         |   0.18640|      0.18527|

Unsupported means too few tuning matches or at least one tuning year with no eligible results.

## How precisely is current K determined?

48 candidates lie within 0.001 MSE of the minimum; their endpoints are 53 and 100.
This is a descriptive tolerance, not a confidence interval. Consult current_curve.csv for membership.
Leaving out one tuning year at a time gives:

| omitted_year|supported |    n| selected_k|
|------------:|:---------|----:|----------:|
|         2021|TRUE      | 2149|         77|
|         2022|TRUE      | 1964|         77|
|         2023|TRUE      | 2042|         77|
|         2024|TRUE      | 1831|         68|
|         2025|TRUE      | 1922|         71|

The current selection is inside the search grid.
K = 1 cannot learn from equal initial integer ratings: half-point changes round back to 1,000.

## Current candidate ratings

| rank|team         | rating|
|----:|:------------|------:|
|    1|England      |   1680|
|    2|India        |   1561|
|    3|South Africa |   1502|
|    4|Pakistan     |   1456|
|    5|West Indies  |   1452|
|    6|Australia    |   1417|
|    7|Nepal        |   1380|
|    8|Portugal     |   1372|
|    9|Ireland      |   1347|
|   10|New Zealand  |   1344|

These replay the full history at the current selected K and update through the stated cutoff.
Each candidate replays the full history at one K; annual K choices are not spliced together.
ratings.csv contains every candidate, including flags for near-minimum choices.

## Reproduction and limitations

Run `make tune-elo` and `make visualize-elo-tuning` from the repository root.
The manifest records settings and hashes; candidate_predictions.csv.gz retains the forecasts.
Methods and reproduction: [pipeline guide](../../../../docs/pipeline.md#selecting-k).

No-results are excluded. All forecasts exclude results completed on or after the match's start date.
The primary model omits venue, lineup, margin and inactivity effects; changing K cannot repair those omissions.
Historical data revisions and opponent mix can affect the results.
Later data are needed for prospective confirmation.
