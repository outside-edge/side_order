# ODI Elo K selection through 2026-10-25

Primary policy: select K each January using the preceding 5 complete years.
Current selection: **K = 27**, using cutoff 2026-01-01 and 644 tuning matches.

Across 1421 evaluation matches in 12 years, mean squared error was 0.21806 versus 0.22945 at K = 100.
The selected policy did better in 11 of 12 evaluation years (0 exact ties).

These are retrospective forecasts with chronological separation, not blinded confirmation.
Squared error measures expected-score accuracy, not three-outcome probability accuracy.
The production pipeline uses the same five-year selection rule.

## Evaluation and tuning-window sensitivity

|scope     | window|    n| years| first_year| last_year| tuned_mse| baseline_mse| neutral_mse| difference| years_better| years_equal|
|:---------|------:|----:|-----:|----------:|---------:|---------:|------------:|-----------:|----------:|------------:|-----------:|
|available |      3| 1421|    12|       2015|      2026|   0.21872|      0.22945|     0.24736|   -0.01072|           10|           0|
|available |      5| 1421|    12|       2015|      2026|   0.21806|      0.22945|     0.24736|   -0.01139|           11|           0|
|available |     10| 1421|    12|       2015|      2026|   0.21776|      0.22945|     0.24736|   -0.01169|           11|           0|
|common    |      3| 1421|    12|       2015|      2026|   0.21872|      0.22945|     0.24736|   -0.01072|           10|           0|
|common    |      5| 1421|    12|       2015|      2026|   0.21806|      0.22945|     0.24736|   -0.01139|           11|           0|
|common    |     10| 1421|    12|       2015|      2026|   0.21776|      0.22945|     0.24736|   -0.01169|           11|           0|

Available rows use each policy's supported folds; common rows use their intersection.
The final year can be partial. Each match has equal weight; annual differences are dependent.

## Annual primary evaluation

| year|supported | selected_k| n_tuning| n_evaluation|partial_year | tuned_mse| baseline_mse|
|----:|:---------|----------:|--------:|------------:|:------------|---------:|------------:|
| 2015|TRUE      |         20|      615|          141|FALSE        |   0.20660|      0.21024|
| 2016|TRUE      |         26|      616|           93|FALSE        |   0.22007|      0.23812|
| 2017|TRUE      |         26|      567|          122|FALSE        |   0.21349|      0.22383|
| 2018|TRUE      |         26|      603|          126|FALSE        |   0.20976|      0.23058|
| 2019|TRUE      |         33|      601|          145|FALSE        |   0.19469|      0.20163|
| 2020|TRUE      |         36|      627|           43|FALSE        |   0.23219|      0.23042|
| 2021|TRUE      |         29|      529|           66|FALSE        |   0.22016|      0.25151|
| 2022|TRUE      |         29|      502|          156|FALSE        |   0.21788|      0.22836|
| 2023|TRUE      |         25|      536|          211|FALSE        |   0.21851|      0.22017|
| 2024|TRUE      |         31|      621|           99|FALSE        |   0.25213|      0.25909|
| 2025|TRUE      |         31|      575|          112|FALSE        |   0.21016|      0.22819|
| 2026|TRUE      |         27|      644|          107|TRUE         |   0.24717|      0.26973|

Unsupported means too few tuning matches or at least one tuning year with no eligible results.

## How precisely is current K determined?

24 candidates lie within 0.001 MSE of the minimum; their endpoints are 19 and 42.
This is a descriptive tolerance, not a confidence interval. Consult current_curve.csv for membership.
Leaving out one tuning year at a time gives:

| omitted_year|supported |   n| selected_k|
|------------:|:---------|---:|----------:|
|         2021|TRUE      | 578|         30|
|         2022|TRUE      | 488|         31|
|         2023|TRUE      | 433|         27|
|         2024|TRUE      | 545|         27|
|         2025|TRUE      | 532|         35|

The current selection is inside the search grid.
K = 1 cannot learn from equal initial integer ratings: half-point changes round back to 1,000.

## Current candidate ratings

| rank|team         | rating|
|----:|:------------|------:|
|    1|India        |   1309|
|    2|New Zealand  |   1275|
|    3|Pakistan     |   1246|
|    4|Australia    |   1225|
|    5|South Africa |   1217|
|    6|Afghanistan  |   1170|
|    7|Sri Lanka    |   1165|
|    8|England      |   1152|
|    9|West Indies  |   1080|
|   10|Bangladesh   |   1076|

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
