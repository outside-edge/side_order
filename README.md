# Side Order

Independent ratings of men's international cricket teams. Elo ratings for Tests,
ODIs, and T20Is are updated weekly, with monthly histories available to download.
Current Test and ODI ratings are also available from GAM, Stan, Glicko-2, and TrueSkill.
These experimental methods have separate scales, uncertainty estimates, and outputs.

[Ratings website](https://outside-edge.github.io/side_order/) ·
[Other Test models](https://outside-edge.github.io/side_order/docs/models.html) ·
[Other ODI models](https://outside-edge.github.io/side_order/docs/models_odi.html) ·
[Latest Elo ratings](out/release/elo/latest.csv) ·
[Monthly history](out/release/elo/monthly.csv) ·
[Match data](data/build/matches.csv)

## Run

Install R 4.6.0, then run from the repository root:

```sh
make sync
make check
make update
```

`make sync` restores the dependencies pinned in `renv.lock`. `make update` fetches
match results from ESPNcricinfo and rebuilds the Elo ratings, figures, and
publication through yesterday. Acquisition, preparation, analysis, visualization,
and publication can also run separately; see the [pipeline guide](docs/pipeline.md)
for commands, data coverage, and validation rules.

Inputs live in `data/`, model results in `out/analysis/`, figures in `figs/`,
and published files in `out/release/`. The pipeline uses R, with Stan model
specifications for Bayesian estimation.

To build and check the website, install Quarto 1.10.19 and run `make site`.
Rendering reads the saved publication without fetching data or refitting models.

## Models

Elo updates ratings after each completed match. Draws and ties count as half-results;
abandoned, cancelled, and no-result matches cause no update. The published Elo
model selects K separately for each format using forecasts from the preceding
five complete years. Each publication replays history with its selected K.
It has no venue adjustment or uncertainty intervals.

The experimental models add different accounts of team strength:

- **GAM:** smooth team trajectories, with home advantage varying by country and ground.
- **Stan:** a dynamic TrueSkill-style model with strength uncertainty and venue and time effects on draws.
- **Glicko-2:** ratings with uncertainty and inactivity handling, using `PlayerRatings`.
- **TrueSkill:** Gaussian skill updates with calendar-time uncertainty, using `TrueSkillThroughTime`.

[Current ratings](https://outside-edge.github.io/side_order/docs/models.html)
use all eligible completed matches in their format through their stated cutoff.
[Reproduction commands](docs/current_models.md) are separate from model evaluation.

The first comparison trains on 1,039 Tests completed before 2024 and forecasts
53 Tests in 2024. This pilot is too small to establish a preferred model.
See the [evaluation scores](out/analysis/models/test/2024-01-01/metrics.csv),
[GAM trajectories](figs/models/test/2024-01-01/gam.png), and
[Stan trajectories](figs/models/test/2024-01-01/stan_dynamic_probit.png).
The [experiment specification](docs/model_experiment.md) gives the assumptions,
validation protocol, and commands to reproduce the fits.

## Documentation

- [Elo K selection](docs/pipeline.md#selecting-k): chronological selection and reproduction commands.
- [Research and evaluation](https://outside-edge.github.io/side_order/docs/research.html): historical forecasts and model development.
- [Pipeline guide](docs/pipeline.md): data sources, Elo specification, updates, and local checks.
- [Modeling agenda](docs/rating_models.md): team versus lineup strength, venue context, and forecast evaluation.
- [Correctness audit](docs/correctness.md): historical bugs, fixes, and numerical verification.

Authors: Gaurav Sood and Derek Willis.
