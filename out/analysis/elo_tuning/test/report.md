# Test Elo K selection through 2026-10-25

Primary policy: select K each January using the preceding 5 complete years.
Current selection: **K = 12**, using cutoff 2026-01-01 and 216 tuning matches.

Across 485 evaluation matches in 12 years, mean squared error was 0.19158 versus 0.20638 at K = 100.
The selected policy did better in 9 of 12 evaluation years (0 exact ties).

These are retrospective forecasts with chronological separation, not blinded confirmation.
Squared error measures expected-score accuracy, not three-outcome probability accuracy.
The production pipeline uses the same five-year selection rule.

## Evaluation and tuning-window sensitivity

|scope     | window|   n| years| first_year| last_year| tuned_mse| baseline_mse| neutral_mse| difference| years_better| years_equal|
|:---------|------:|---:|-----:|----------:|---------:|---------:|------------:|-----------:|----------:|------------:|-----------:|
|available |      3| 485|    12|       2015|      2026|   0.19155|      0.20638|     0.21701|   -0.01483|            9|           0|
|available |      5| 485|    12|       2015|      2026|   0.19158|      0.20638|     0.21701|   -0.01480|            9|           0|
|available |     10| 485|    12|       2015|      2026|   0.19008|      0.20638|     0.21701|   -0.01630|            9|           0|
|common    |      3| 485|    12|       2015|      2026|   0.19155|      0.20638|     0.21701|   -0.01483|            9|           0|
|common    |      5| 485|    12|       2015|      2026|   0.19158|      0.20638|     0.21701|   -0.01480|            9|           0|
|common    |     10| 485|    12|       2015|      2026|   0.19008|      0.20638|     0.21701|   -0.01630|            9|           0|

Available rows use each policy's supported folds; common rows use their intersection.
The final year can be partial. Each match has equal weight; annual differences are dependent.

## Annual primary evaluation

| year|supported | selected_k| n_tuning| n_evaluation|partial_year | tuned_mse| baseline_mse|
|----:|:---------|----------:|--------:|------------:|:------------|---------:|------------:|
| 2015|TRUE      |         19|      209|           43|FALSE        |   0.19509|      0.20247|
| 2016|TRUE      |          8|      209|           47|FALSE        |   0.18753|      0.19991|
| 2017|TRUE      |          8|      217|           47|FALSE        |   0.16648|      0.17798|
| 2018|TRUE      |         15|      222|           48|FALSE        |   0.22977|      0.26410|
| 2019|TRUE      |         10|      226|           39|FALSE        |   0.18547|      0.22312|
| 2020|TRUE      |         13|      224|           22|FALSE        |   0.19149|      0.17590|
| 2021|TRUE      |         15|      203|           44|FALSE        |   0.16424|      0.16316|
| 2022|TRUE      |         19|      200|           43|FALSE        |   0.17900|      0.20329|
| 2023|TRUE      |         15|      196|           34|FALSE        |   0.19826|      0.20284|
| 2024|TRUE      |         15|      182|           53|FALSE        |   0.21443|      0.24693|
| 2025|TRUE      |         12|      196|           42|FALSE        |   0.17052|      0.16407|
| 2026|TRUE      |         12|      216|           23|TRUE         |   0.22709|      0.24277|

Unsupported means too few tuning matches or at least one tuning year with no eligible results.

## How precisely is current K determined?

16 candidates lie within 0.001 MSE of the minimum; their endpoints are 8 and 23.
This is a descriptive tolerance, not a confidence interval. Consult current_curve.csv for membership.
Leaving out one tuning year at a time gives:

| omitted_year|supported |   n| selected_k|
|------------:|:---------|---:|----------:|
|         2021|TRUE      | 172|          8|
|         2022|TRUE      | 173|         23|
|         2023|TRUE      | 182|         13|
|         2024|TRUE      | 163|         21|
|         2025|TRUE      | 174|         12|

The current selection is inside the search grid.
K = 1 cannot learn from equal initial integer ratings: half-point changes round back to 1,000.

## Current candidate ratings

| rank|team         | rating|
|----:|:------------|------:|
|    1|Australia    |   1176|
|    2|India        |   1121|
|    3|South Africa |   1118|
|    4|England      |   1089|
|    5|New Zealand  |   1077|
|    6|Sri Lanka    |    985|
|    7|Pakistan     |    963|
|    8|Afghanistan  |    956|
|    9|Ireland      |    950|
|   10|West Indies  |    912|

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
