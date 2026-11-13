# Correctness audit

The audit separates errors in result coding from changes in sample, chronology,
model specification, and output extraction. Previously committed ratings remain in Git history; the maintained pipeline writes separate model outputs.

## Verified legacy defects

The prepared CSV contains 62,591 unique match IDs. Its core fields agree with the
raw legacy CSV after matching by ID and normalizing missing-value representation.
The file begins with a UTF-8 byte-order mark. The legacy importer now explicitly
uses `fileEncoding = "UTF-8-BOM"`; regression tests check that `team1` exists and
has the expected length.

The original winner assignment treated every result that was not a team-1 win
as a team-2 win, except outcomes containing “drawn”. Across the men's international
subsets, this affected **415 matches**:

| Format | No result / abandoned / canceled | Tied | Total |
| --- | ---: | ---: | ---: |
| Test | 12 | 2 | 14 |
| ODI | 273 | 39 | 312 |
| T20I | 70 | 19 | 89 |
| Total | 355 | 60 | 415 |

The corrected legacy sample has 7,735 rated matches: 2,416 Tests, 4,162 ODIs, and
1,157 T20Is. All 60 ties score 0.5. The 355 matches without a result do not update
ratings. These are executable regression checks, not documentation assertions.

Using the same legacy sample, original date ordering, and EloRating defaults,
changing only outcome handling changes final ratings materially. Examples:
Pakistan's Test rating 1,079 → 1,108; Sri Lanka's ODI rating 1,268 → 1,157;
South Africa's ODI rating 1,214 → 1,319; West Indies' T20I rating 1,043 → 1,158.
These are controlled coding comparisons, not the newly expanded pipeline's ratings.
An uncertainty calculation must use the corrected outcomes; consistency with a
known coding error is not a reason to retain it.

## Chronology and numerical reproduction

The legacy monthly extraction requests `NA.interpolate = TRUE` and a 30-day
range. This can use future matches and average dates after the stated snapshot.
A two-team example gives 1,050 by carrying forward the rating on January 15,
versus 1,021 with interpolation using a later match. The maintained pipeline
extracts from its completed-match update ledger instead.

Running the current EloRating version against the legacy extraction does not
exactly reproduce the committed latest monthly values. Maximum absolute
mismatches are 17 Test points, 25 ODI points, and 53 T20I points. The old package
version and exact generation provenance were not pinned. This discrepancy is
unresolved and is not attributed solely to the result-coding defect.

The new engine is checked against an independent `EloRating::elo.seq()` reference
for all 100 teams across the full saved 2025 Test and T20I tables (597 rated
matches). Additional tests truncate the data at historical cutoffs and confirm
that adding later matches cannot change earlier snapshots. A single-date dataset
exposes a dimension-dropping failure in EloRating 0.46.18's sequence wrapper;
the maintained pipeline uses its documented `e.single()` primitive, preserving
the package's update arithmetic without relying on that wrapper's date matrices.

The expanded results cannot be expected to equal the old published series. It
starts at the source's earliest international years, adds subsequent results,
uses completion dates, joins team aliases by ID, fixes outcomes, and changes
monthly extraction. Each of those choices is explicit in the manifest/README.

The full Test history through October 24, 2026 contains 2,638 rated matches.
Every update agrees exactly with `elo.seq()`. All 2,416 rated Tests shared with
the legacy dataset agree on outcomes; its 12 abandoned/canceled Tests are not
listed in the annual results tables. The ODI overlap also exposes different
identifier namespaces: for example, Africa XI is API ID 4058 in the legacy data
and profile-link ID 213709 in the annual tables. An ID-only comparison across
these sources can therefore report a false outcome disagreement. Participant
identities must be reconciled when adding legacy covariates.

The complete build through October 24, 2026 contains 11,900 matches, including
280 no-results. The independent sequence comparison checked both teams' ratings
before and after every rated match:

| Format | Rated matches | Rating values checked | Maximum absolute difference |
| --- | ---: | ---: | ---: |
| Test | 2,638 | 10,552 | 0 |
| ODI | 4,868 | 19,472 | 0 |
| T20I | 4,114 | 16,456 | 0 |

Historical snapshots at December 31, 2021 and December 31, 2025 also match fits
that exclude all subsequent matches, in every format. The downloaded tables
contain every numbered source match from 1 through Test 2,638, ODI 5,047, and
T20I 4,220, without duplicate numbers or gaps. Five records fall after the build
cutoff and are excluded. These checks establish consistency with this source,
not independent certification of every match's underlying scorecard.

## Other model work

The historical Glickman script uses `PlayerRatings::glicko2()` but repeats the
old outcome coding. Its period-to-date join can duplicate team-date rows, and
its purported Elo comparison reads the Glicko CSV again. The Stan driver also
uses the old outcome recoding and refers to model files not present in this
repository. These scripts are exploratory, not verified publication adapters.

Their eventual adapters should consume the shared validated match identities
and outcomes, with model-specific treatment of rating periods, ties/draws,
inactivity, and covariates. Glickman and Stan outputs must have independent
specifications, checks, diagnostics, and publication directories. No claim of
numerical equivalence between these different methods is implied.

The historical all-matches request list contains 63,360 unique IDs; 810 requested
IDs are absent from the 62,591 loaded records, and 41 loaded IDs were not in that
list. That is a further reason to document coverage of the new source explicitly,
rather than assume the legacy extraction was complete.
