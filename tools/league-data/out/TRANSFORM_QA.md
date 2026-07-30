# TRANSFORM_QA — league template build

> **DO NOT BUNDLE.** This report is a tool artifact. It contains the answer key
> for the recognizability spot-check (real names) in the final section and must
> never enter an app target's resources. `league_2026_dev.json` is DEBUG-only;
> only `league_2026_publish.json` ships in a Release build.

- built: `2026-07-30T20:09:04Z` (the templates themselves are byte-identical on every rebuild — their `generated` stamp is the source snapshot's, `2026-07-29T13:59:05Z`)
- globalSeed: `20260729` (deterministic — re-running reproduces both files)
- source: `tools/league-data/raw/league_raw_2026.json` (schemaVersion 2, snapshot 2026-02-28)
- outputs: `out/league_2026_dev.json` (devProfile), `out/league_2026_publish.json` (publishProfile)
- teams 32 / players 1807 / coaches 95

## 1. Gate results

| # | Gate | Result | Detail |
|---:|---|:-:|---|
| 1 | `schema-validate` | PASS | dev + publish share one schema; 32 teams; ratings 40-99; potential >= rating; no null colleges; identity keys per profile (dev carries the DEV-ONLY `ownerName`; both carry `ownerGender`, publish carries no owner NAME) |
| 2 | `publish-name-levenshtein>=3` | PASS | 1902 generated publish names checked against a 2048-name blocklist; minimum distance >= 3 |
| 3 | `publish-no-real-name-substring` | PASS | 5642 identity-bearing strings (player + coach names, team nicknames, pick trade notes) scanned: no real full name and no real surname (>=4 chars) appears in any of them |
| 4 | `publish-names-unique` | PASS | 1902 names, all distinct |
| 5 | `publish-no-same-initials` | PASS | no publish player shares initials with his real counterpart at the same team + position |
| 6 | `publish-bio-jitter>=3-fields` | PASS | every publish player carries >= 3 transformed bio fields (min 4, mean 6.36) |
| 7 | `publish-ovr-arcs-only` | PASS | publish carries OVR arcs only — statLines null and no gp/gs on any arc row |
| 8 | `calibration-bands` | PASS | league mean 71.01 (band (70.0, 72.0)), sd 8.95 (band (7.6, 10.0)), team spread 4.90 (band (4.0, 6.0)), Spearman(team OVR, 2025 wins) 0.94 (min 0.55) |
| 9 | `tier-structure` | PASS | depth-index means vs the random generator: idx0 79.8 (ref 78.5, +1.38, n=589), idx1 71.0 (ref 70.7, +0.33, n=463), idx2 64.1 (ref 63.5, +0.64, n=755); by role backup 65.9 (n=666), depth 60.2 (n=122), rotation 66.3 (n=209), starter 78.0 (n=810); league max 96, 90+ count 39 |
| 10 | `depth-order-from-ratings` | PASS | depth rank is the rating order on all 32 rosters; 27 QA depth suspects resolved (0 inversions left); CIN QB: OK — QB1 78 OVR vs QB3 71 OVR; WAS QB: OK — QB1 88 OVR vs QB2 76 OVR |
| 11 | `jersey-uniqueness` | PASS | no duplicate jersey number on any roster in either profile (the 2 raw collisions were reassigned) |
| 12 | `publish-pick-notes-clean` | PASS | every 2026 pick trade note is reduced to the ownership chain ('from X via Y'); no player names survive |
| 13 | `publish-draft-slot-fuzzed` | PASS | 1338 drafted players; 0 keep their real overall pick (round preserved, slot moved within round) |
| 14 | `publish-jersey-reissued` | PASS | no publish player wears his real number (the Keller/Davis 'number + position + bio' combination is broken); numbers stay inside the position's legal NFL bands and unique per roster |
| 15 | `publish-no-notes-payload` | PASS | no publish player carries a `notes` payload (the dev profile keeps 553 of them, incl. the real injured-reserve flag, and is DEBUG-only) |
| 16 | `publish-name-recombination>=3` | PASS | all 239 x 385 = 92015 recombinations of the shipped first/last tokens are Levenshtein >= 3 from every real name — the importer generates 417 support-staff coaches by drawing the two halves independently, and those names never reach a bundle scan |
| 17 | `publish-coach-tenure-moved` | PASS | all 95 publish coaches with a real `sinceYear` moved by exactly ±1 (spec §4); the direction is picked among the moves that survive the [1990, leagueYear] clamp, so a 2026 hire cannot be clamped back onto his real tenure |
| 18 | `age-profile-in-drift-band` | PASS | mean age 26.7 (band 25.0-28.0), 33+ share 5.4% (ceiling 8.0%), roster sizes [55, 56, 57]. Reference random league: mean 25.8 / 3.2% at 33+ over exactly 53 men. The template is OLDER on purpose (real pyramid, real 53+IR rosters) and its first offseason retires ~86 players against the random league's ~46 — an ACCEPTED, recorded difference, not a calibration target; see TRANSFORM_QA §7 |
| 19 | `face-preassignment` | PASS | dev 1902 unique faces (1807p + 95c), band 82.1%, build 88.5%, exact bucket 74.1%, 135 reserve; publish 1902 unique faces (1807p + 95c), band 84.5%, build 88.6%, exact bucket 76.2%, 135 reserve; 163 female coach faces in the pool (ids 2560+), 0 baked; buckets cross-checked against 3712 generated faces; pool 2048 generated + 512 reserve + 1024 extended + 128 female-only |

**Verdict: ALL GATES PASS.**

## 2. Calibration

Binding decision: the template league must sit where the *random* `LeagueGenerator` league sits, so every balance threshold in the engine behaves identically across all three league sources. It is **not** recalibrated to `DEVELOPMENT_NFL_REFERENCE.md` section-8 absolute bands.

Method: the tool Monte-Carlos the Swift generator (140 reps) over *this* league's actual composition — same positions, same per-team depth counts, same real ages — and then rank-maps each position's players onto that position's reference quantile curve. The level and shape therefore match by construction; only the ORDERING inside a position comes from the production model.

- league mean OVR **71.01** (reference generator 71.01, band (70.0, 72.0))
- league sd **8.95** (reference generator 8.85, band (7.6, 10.0))
- reference generator quality pyramid (DEVELOPMENT_NFL_REFERENCE §8): 90+ 1.84% [1-2] · 80+ 17.07% [12-16] · 75+ 34.76% [30-40] · sub-65 23.34% [~25] · range 40-97
- team mean spread **4.90** OVR (target 5.0, band (4.0, 6.0))
- OVR 90+: 39 players; max 96; min 45

### Team strength vs real 2025

| Team | mean OVR | 2025 record | playoff finish |
|---|---:|---|---|
| SEA | 73.3 | 14-3 | Won Super Bowl LX |
| CHI | 72.9 | 11-6 | Lost Divisional round |
| NE | 72.7 | 14-3 | Lost Super Bowl LX |
| HOU | 72.6 | 12-5 | Lost Divisional round |
| DEN | 72.6 | 14-3 | Lost Conference Championship |
| LA | 72.4 | 12-5 | Lost Conference Championship |
| BUF | 72.1 | 12-5 | Lost Divisional round |
| PIT | 72.1 | 10-7 | Lost Wild Card round |
| JAX | 72.0 | 13-4 | Lost Wild Card round |
| PHI | 71.8 | 11-6 | Lost Wild Card round |
| DET | 71.8 | 9-8 | — |
| SF | 71.6 | 12-5 | Lost Divisional round |
| IND | 71.5 | 8-9 | — |
| LAC | 71.4 | 11-6 | Lost Wild Card round |
| TB | 71.4 | 8-9 | — |
| DAL | 71.3 | 7-9-1 | — |
| ATL | 71.3 | 8-9 | — |
| MIN | 71.1 | 9-8 | — |
| BAL | 71.0 | 8-9 | — |
| GB | 71.0 | 9-7-1 | Lost Wild Card round |
| CAR | 70.8 | 8-9 | Lost Wild Card round |
| MIA | 70.4 | 7-10 | — |
| CIN | 70.4 | 6-11 | — |
| NO | 70.0 | 6-11 | — |
| KC | 69.8 | 6-11 | — |
| NYG | 69.5 | 4-13 | — |
| CLE | 69.4 | 5-12 | — |
| WAS | 69.3 | 5-12 | — |
| TEN | 69.0 | 3-14 | — |
| LV | 68.7 | 3-14 | — |
| ARI | 68.7 | 3-14 | — |
| NYJ | 68.4 | 3-14 | — |

## 3. Ratings derivation (position heuristics)

Per player: `quality = (1 - w_ped) * (0.60 * production + 0.40 * role) + w_ped * draftPedigree`, with `w_ped = 0.32 * exp(-yearsPro / 2.2)` so draft capital carries a rookie and is irrelevant to a nine-year veteran. A small age term (half of the generator's own `ageLevelShift`) keeps the age/rating relationship the engine sustains.

`production` is never an absolute number: every metric below is converted to a percentile inside `(position family, season)`, weighted, then shrunk toward the median by a confidence factor built from games played and snap share — a four-game cameo cannot make or break a rating. Seasons are recency-weighted `0.62^(2025 - year)`.

| Family | Metrics (weight) |
|---|---|
| QB | `rating` 0.30, `ypa` 0.18, `tdint` 0.17, `passYpg` 0.23, `rushProd` 0.12 |
| RB | `scrimYpg` 0.42, `ypc` 0.20, `touchesPg` 0.24, `recProd` 0.14 |
| WR | `recYpg` 0.44, `recPg` 0.19, `tgtPg` 0.20, `ypr` 0.17 |
| TE | `recYpg` 0.40, `recPg` 0.20, `tgtPg` 0.22, `ypr` 0.18 |
| OL | `snapShare` 0.52, `snapsPg` 0.26, `cleanPlay` 0.22 |
| DL | `sackPg` 0.34, `tflPg` 0.20, `tklPg` 0.14, `snapShare` 0.26, `ffPg` 0.06 |
| LB | `tklPg` 0.33, `sackPg` 0.15, `tflPg` 0.12, `coverPg` 0.14, `snapShare` 0.26 |
| DB | `coverPg` 0.30, `tklPg` 0.19, `snapShare` 0.41, `sackPg` 0.10 |
| K | `fgPct` 0.52, `fgLong` 0.20, `fgMade` 0.28 |
| P | `puntAvg` 0.55, `in20Rate` 0.35, `puntsPg` 0.10 |

`areaHints` are mean-zero integer deltas (±8 max) on the game's own position-attribute names, so they tilt the shape without moving the solved overall: QB accuracy vs arm vs scrambling from comp% / yds-per-attempt / rush profile and sack rate; RB elusiveness vs power from yards-per-carry, weight and receiving share; WR hands vs deep from catch rate and yards-per-reception; TE blocking vs receiving from target rate; OL pass-set vs pull from the exact position, weight and penalty rate; DL power vs finesse from weight against sack rate; LB coverage vs blitz from passes-defensed against sacks; DB coverage vs run-support from (PD + 2.5·INT)/g against tackles/g, plus height for press.

`potential` is the phase-2 veteran rule ported verbatim (`LeagueGenerator.veteranPotential`): past the position's peak window the ceiling is `overall + U(0,3)`; inside it, `overall + max(0, N(mu, 4))` with `mu = max(2, 14 - 2.5·(age - 22))`.

`careerArc` = per-season production percentile → OVR band → ±2 seeded jitter, anchored so the 2025 row lands within ±3 of `ratingTarget`. In the publish file this is the ONLY career record that ships.

## 4. QA_REPORT carry-in conditions

| # | Carry-in | Handling |
|---:|---|---|
| 1 | `role` is a one-season volume ranking, 27/768 starter slots suspect | Production model is rate-based, and depth order is **re-derived from the ratings** in both profiles (`depthRank` / `role`); the raw values survive only as `roleHint` / `depthRankHint`. All 27 machine-listed suspects are lifted above their listed starter in score space; CIN QB and WAS QB are additionally forced by an explicit hand override. |
| 2 | 2 jersey collisions (BUF #23, IND #17) | Higher-rated player keeps the number, the other is reassigned to the lowest free number on that roster. |
| 3 | 5 null colleges | Replaced by the `"No College"` sentinel; in publish they go through the same same-tier swap as everyone else, because a "No College" flag on 5 players is itself an identifier. Transfer chains (`"LSU; Ohio State"`) are reduced to the school of record, which nflverse lists FIRST. |
| 4 | OL `gs` is a `snapStart50` proxy | OL production is scored on snap share / snaps-per-game / penalty rate — never on `gs`. |
| 5 | Anonymization is mandatory | Mandatory for the SHIPPED profile: the publish file passes gates 2-7 and 12-17 above. The dev file is real names throughout (decision 2026-07-30) and is DEBUG-only — `check_bundle.sh` proves it is absent from a Release product. |

- HAND CIN QB: Joe Burrow > Joe Flacco (+6.0) — Franchise QB; led on rate (.878 snap share vs .778) but was out-volumed.
- HAND WAS QB: Jayden Daniels > Marcus Mariota (+6.0) — Franchise QB; led on rate (.903 vs .745) but was out-volumed.
- QA-suspect ARI CB: Garrett Williams > Denzel Burke (+2.26)
- QA-suspect BUF OLB: Shaq Thompson > Dorian Williams (+2.48)
- QA-suspect DAL CB: Shavon Revel Jr. > Reddy Steward (+3.21)
- QA-suspect DET CB: D.J. Reed > Rock Ya-Sin (+3.01)
- … 18 further depth corrections

## 5. Anonymization

**devProfile** (`league_2026_dev.json`, DEBUG builds only): **not anonymized at all** (decision 2026-07-30). Real player and coach names verbatim, the real 32 club identities (the same city + nickname pairs `NFLTeamData.swift` gives the random league), the real principal owners (`DEV_OWNERS` → `identity.ownerName` + `identity.ownerGender`, the one thing the raw scrape does not carry), exact stat lines in `statLines`, real jerseys, real draft slots. It is the developer's own NFL and is filtered out of a Release product on two independent levels — `EXCLUDED_SOURCE_FILE_NAMES` and the `#if DEBUG` source guards — which `tools/league-data/check_bundle.sh` check (b) proves against a built `.app`. Consequence to know: the importer's `SupportStaffNamePool` harvests the template's own name tokens, so a DEBUG career's 417 support-staff coaches carry real-adjacent recombinations. That is per-template and cannot reach the publish pools (gate 16 is publish-only by design).

**publishProfile** (`league_2026_publish.json`, bundled always), per `docs/ANONYMIZATION_SPEC.md`:

- Names drawn independently from a 241 × 390 pool, culturally mixed and blocklist-filtered and far larger than the game's own `RandomNameGenerator` pool. Seed = SHA-256(globalSeed | real name | team | pos).
- Blocklist: 2048 real names — every player and coach in the raw snapshot plus a curated list of notable NFL figures of the last ~15 years.
- Guards: full-name Levenshtein ≥ 3 to every blocklisted name; generated surname not equal to and not a 1-edit variant of any real surname; no duplicate generated names; no same-initials + same-team + same-position hit.
- Guard 1c — **recombination**: the emitted first / last tokens become a POOL. `LeagueTemplateImporter.SupportStaffNamePool` harvests them and draws the halves independently for 417 runtime support-staff coaches, so the constraint is not "the pairs I emit are clean" but "every pair the emitted tokens can form is clean". The factory refuses any token that would break that (16 rejections this build), and gate 16 re-derives the whole cross product. Without it `Cedric`+`Skillman`, `Zaire`+`Frankland` and `Broderick`+`Warrington` were all reachable at 2 edits from a real player — at run time, where no bundle scan can see them.
- Bio jitter: age ±1 (exactly balanced league-wide, so the age pyramid is preserved), `yearsPro` re-clamped to `[0, age-20]`, college swapped for a different school of the same tier (P5/G5/FCS; two players who really shared a school and a draft class never share the replacement), draft year and round kept with the pick fuzzed ±8 inside the round, height ±1 in, weight ±2-4 %.
- Jersey numbers reissued from the position's legal NFL bands, unique per roster, never the real number. `ANONYMIZATION_SPEC.md` section 0 does not list the number, but the precedent it cites (Keller / Davis v. EA) turns on exactly "number + position + bio + stats" — a #9 quarterback in Cincinnati is identifiable to any fan — so this tool transforms it.
- Careers: OVR arcs only. `statLines` is `null` and no arc row carries games played / started.
- `notes` is `null` for every publish player (gate 15). The dev profile keeps `undrafted` / `finished 2025 on injured reserve`; the IR flag is a real medical event for a named person, which section 3 does not ship, and against the team + position + depth rank the profile keeps by design it identified single players straight out of the bundle.
- Coaches: fictional names, `sinceYear` ±1 with the DIRECTION chosen among the moves that survive the [1990, leagueYear] clamp (drawing first and clamping second returned the real year for every 2026 hire), offense/defense background and scheme identity kept, lineage notes dropped.
- Team identities: real cities kept (facts / the game's own setup), nicknames fully fictional. No `ownerName` key: the importer draws all 32 owners from `LeagueGenerator`'s fictional, gate-E-checked pools — from the pool matching `identity.ownerGender`, which IS kept (a fact about the club, like its scheme; the importer cannot roll for it because the owner is built on the seeded stream, and rolling would move every attribute after it).
- Pick trade notes reduced to the ownership chain (`from SEA via JAX`); the prose that names players is dropped.

## 6. Recognizability spot-check — 20-player blind sample

Read this table without scrolling to the answer key. Per `ANONYMIZATION_SPEC.md` section 6.4, a reviewer who knows the NFL must not be able to name the real counterpart from the in-app profile alone. Any confident hit means the offending field's jitter needs tightening and a regeneration.

| # | Name | Team | Pos | # | Age | Exp | College | Ht/Wt | Draft | OVR | Pot |
|---:|---|---|---|---:|---:|---:|---|---|---|---:|---:|
| 1 | Torrance Montague | HOU | DE | 78 | 25 | 3 | Arizona | 6-3 / 236 | 2023 R1 #11 | 80 | 82 |
| 2 | Jarell Huddleston | LV | WR | 11 | 32 | 11 | Michigan State | 5-11 / 178 | 2015 R3 #65 | 72 | 72 |
| 3 | Teagan Elmendorf | WAS | DE | 63 | 31 | 8 | Texas Tech | 6-4 / 294 | 2018 R4 #106 | 69 | 69 |
| 4 | Reece Waldgrave | PHI | LT | 79 | 27 | 7 | Grambling State | 6-9 / 373 | 2018 R7 #226 | 85 | 88 |
| 5 | Osric Sidebottom | PHI | DE | 61 | 25 | 3 | Georgia | 6-3 / 285 | 2023 R7 #243 | 71 | 73 |
| 6 | Cormac Dowdell | MIA | RB | 36 | 21 | 1 | Penn State | 6-2 / 220 | UDFA | 48 | 50 |
| 7 | Deshun Gantry | TEN | DE | 98 | 26 | 6 | Rutgers | 6-4 / 283 | 2020 R4 #138 | 65 | 66 |
| 8 | Jamari Tunstall | JAX | RB | 34 | 28 | 5 | Auburn | 5-10 / 195 | 2021 R1 #26 | 85 | 85 |
| 9 | Kai Thistlewood | DAL | TE | 43 | 28 | 3 | Rutgers | 6-4 / 256 | 2023 R2 #52 | 72 | 73 |
| 10 | Quade Draycott | LAC | FB | 47 | 26 | 3 | Colorado State | 6-3 / 310 | 2023 R6 #199 | 83 | 85 |
| 11 | Sebastien Waterhouse | ARI | CB | 32 | 26 | 5 | Middle Tennessee State | 6-0 / 184 | 2021 R4 #116 | 63 | 64 |
| 12 | Dallin Estabrook | CLE | WR | 80 | 24 | 1 | Penn State | 5-8 / 165 | UDFA | 52 | 53 |
| 13 | Ramiro Carrington | ARI | QB | 10 | 25 | 2 | Washington State | 6-3 / 223 | UDFA | 57 | 59 |
| 14 | Killian Wendover | GB | OLB | 58 | 27 | 5 | Iowa State | 6-4 / 241 | 2021 R6 #193 | 65 | 66 |
| 15 | Kester Derringer | NYJ | DT | 98 | 25 | 3 | Boston College | 6-3 / 347 | 2023 R1 #25 | 61 | 62 |
| 16 | Carmine Woolridge | NO | MLB | 47 | 27 | 5 | Florida State | 6-3 / 232 | 2021 R2 #53 | 77 | 85 |
| 17 | Phineas Wimberly | LAC | FS | 39 | 28 | 5 | Virginia | 5-11 / 195 | 2021 R3 #98 | 79 | 80 |
| 18 | Orion Reinholt | SF | MLB | 57 | 34 | 11 | Georgia | 6-0 / 225 | 2015 R2 #48 | 74 | 76 |
| 19 | Davion Ragsdale | NYJ | RB | 36 | 25 | 4 | Arizona | 6-0 / 227 | 2022 R2 #37 | 83 | 86 |
| 20 | Verner Studebaker | SEA | RB | 24 | 27 | 4 | N.C. State | 6-1 / 194 | 2022 R3 #76 | 67 | 67 |

### Answer key — real counterparts (DO NOT BUNDLE)

| # | Publish name | Real name | Real college | Real ht/wt | Real draft |
|---:|---|---|---|---|---|
| 1 | Torrance Montague | Will Anderson Jr. | Alabama | 6-4 / 243 | 2023 R1 #3 |
| 2 | Jarell Huddleston | Tyler Lockett | Kansas State | 5-10 / 182 | 2015 R3 #69 |
| 3 | Teagan Elmendorf | Jalyn Holmes | Ohio State | 6-5 / 283 | 2018 R4 #102 |
| 4 | Reece Waldgrave | Jordan Mailata | No College | 6-8 / 365 | 2018 R7 #233 |
| 5 | Osric Sidebottom | Moro Ojomo | Texas | 6-3 / 292 | 2023 R7 #249 |
| 6 | Cormac Dowdell | Donovan Edwards | Michigan | 6-1 / 212 | UDFA |
| 7 | Deshun Gantry | James Lynch | Baylor | 6-4 / 295 | 2020 R4 #130 |
| 8 | Jamari Tunstall | Travis Etienne | Clemson | 5-10 / 200 | 2021 R1 #25 |
| 9 | Kai Thistlewood | Luke Schoonmaker | Michigan | 6-5 / 250 | 2023 R2 #58 |
| 10 | Quade Draycott | Scott Matlock | Boise State | 6-4 / 300 | 2023 R6 #200 |
| 11 | Sebastien Waterhouse | Darren Hall | San Diego State | 6-0 / 190 | 2021 R4 #108 |
| 12 | Dallin Estabrook | Gage Larvadain | South Carolina; Miami (Ohio) | 5-8 / 171 | UDFA |
| 13 | Ramiro Carrington | Kedon Slovis | BYU; Pittsburgh; USC | 6-2 / 215 | UDFA |
| 14 | Killian Wendover | Nick Niemann | Iowa | 6-3 / 235 | 2021 R6 #185 |
| 15 | Kester Derringer | Mazi Smith | Michigan | 6-3 / 337 | 2023 R1 #26 |
| 16 | Carmine Woolridge | Pete Werner | Ohio State | 6-3 / 242 | 2021 R2 #60 |
| 17 | Phineas Wimberly | Elijah Molden | Washington | 5-10 / 190 | 2021 R3 #100 |
| 18 | Orion Reinholt | Eric Kendricks | UCLA | 6-0 / 232 | 2015 R2 #45 |
| 19 | Davion Ragsdale | Breece Hall | Iowa State | 5-11 / 220 | 2022 R2 #36 |
| 20 | Verner Studebaker | Velus Jones Jr. | Tennessee; USC | 6-0 / 200 | 2022 R3 #71 |

## 7. Age profile — a KNOWN, ACCEPTED difference from the random league

The calibration decision binds OVR **level and spread**. It does not bind the age pyramid, and the two league sources deliberately disagree there:

| | Fixed 2026 template | Random `LeagueGenerator` |
|---|---:|---:|
| mean age | **26.7** | 25.8 |
| median age | **26** | 25 |
| share 33+ | **5.4%** | 3.2% |
| roster size | **55-57** (real 53-man + IR) | exactly 53 |
| measured season-1 retirements | **~86** | ~46 |
| measured season-1 draft intake | **288** | 250 |

Age histogram: 21:54, 22:94, 23:152, 24:186, 25:231, 26:251, 27:199, 28:159, 29:130, 30:115, 31:81, 32:58, 33:33, 34:18, 35:12, 36:13, 37:9, 38:5, 40:3, 41:1, 42:2, 45:1

Why it is not "fixed": `ANONYMIZATION_SPEC.md` section 2 requires the age pyramid to be PRESERVED (that is why the ±1 jitter is exactly balanced), and the pyramid is the realism the template exists to deliver. Reshaping it onto `LeagueGenerator.randomAge` — which is `min(U, U)`, deliberately young — would replace real 2026 rosters with a synthetic age curve.

What it costs: `PlayerRetirementEngine.retirementProbability` is `0.04 + yearsPastPeak * 0.19`, so a Fixed 2026 career's FIRST offseason cycles about 4.8 % of the league out against the random league's 2.7 %, and backfills from a draft pipeline calibrated for 250. It is a season-1 churn spike, not a permanent divergence: by the end of season 1 the 33+ share is 0.8 %, rosters are 53/53, and league mean OVR lands 75.68 (template) vs 75.97 (random). Both leagues also sit above `DEVELOPMENT_NFL_REFERENCE.md` section 8's <=2 % band for 33+, which the deferred P1 recalibration wave owns — fixing the template alone would just move it away from the random league it is required to match.

Gate 18 (`age-profile-in-drift-band`) therefore records the numbers and only fails on DRIFT (mean outside 25.0-28.0, or 33+ above 8 %), so a future raw snapshot cannot quietly make this worse.

## 8. Face pre-assignment (phase 4)

Every template person carries the face id he will wear. This is not a convenience: `LeagueTemplateImporter` gives each imported `Player` / `Coach` a FRESH `UUID()`, and the runtime picker hashes exactly that UUID — so a fixed league that assigned faces at runtime would show different portraits every time it was created. Baking the ids is what makes the fixed league fixed all the way down to the faces.

**Pool decision: the library is extended to 3 712 ids** (`face_00000`-`face_03711`). The seed yields 1672 player-age faces in the default `--count 2048` range against 1807 template players, so per-person uniqueness is arithmetically impossible there. Sharing was rejected (a duplicated portrait inside ONE league reads as a bug), so the transform draws the overflow from a reserved range, `face_02048`-`face_03711`, which `python3 tools/faces/generate_faces.py --count 3584` produces later. Ids are stable and the manifest is append-only, so extending costs nothing already generated.

The last 1024 ids (`face_02560`-`face_03711`) are the **female extension range**: a coach face there spends one extra draw on gender at 22%, and it is the library's only source of female portraits. The template never reaches it — its coaches anonymize real male head coaches and allocation is lowest-id-first — so the range exists purely for the women a career hires at run time.

| pool half | age band | faces `--count 2048` | + ids 2048+ | template demand |
|---|---|---:|---:|---:|
| player | 20-24 | 628 | +478 | 486 |
| player | 25-29 | 656 | +482 | 970 |
| player | 30-36 | 388 | +292 | 351 |
| coach | 38-50 | 170 | +175 | 47 |
| coach | 50-68 | 206 | +237 | 48 |

- assigned: **1902 unique faces** (1807 players + 95 coaches), zero shared, zero role mismatches (no player wears a coach-age face)
- bucket quality: age band exact on **84.5 %**, build exact on **88.6 %**, both on 76.2 %. The rest take the nearest neighbouring bucket — build is relaxed BEFORE age, exactly as `FaceLibrary.pickLocked` does at runtime.
- reserve range: **135 people** — the whole 122-man `depth` tier plus the 13 lowest-rated backups. Allocation runs starters → rotation → backups → depth and takes the lowest free id first, so the ids whose pictures may not exist yet land on the least visible people, and the ids generated first land on the most visible ones.
- left for the career: **281** generated-range and 1529 faces at `face_02048`+ (reserve plus the female extension range) for draft classes, UDFAs, hired coordinators and the 417 support-staff coaches the importer creates.

Nothing here needs an image. A face's bucket is a pure function of `(face seed, id)`, so this runs while the library is still generating, and `PersonFaceView` draws a silhouette for any id whose HEIC has not landed. Gate 19 cross-checks the bucket maths against every face the generator has actually produced.

One coupling to know about: a template coach has no age in the file — `LeagueGenerator.generateCoach` draws it. The tool replays that single draw (SplitMix64 + Swift's 64-bit `Int.random`) to pick an age-correct face. It is the FIRST draw of the coach's stream only because `nameOverride` short-circuits the name pools for hc/oc/dc; a new draw inserted ahead of it would push template coach faces onto the wrong age band (gate 19's band share would drop to ~50 %).

## 9. Build log

- raw: 32 teams / 1807 players / 7526 season rows
- HAND CIN QB: Joe Burrow > Joe Flacco (+6.0) — Franchise QB; led on rate (.878 snap share vs .778) but was out-volumed.
- HAND WAS QB: Jayden Daniels > Marcus Mariota (+6.0) — Franchise QB; led on rate (.903 vs .745) but was out-volumed.
- QA-suspect ARI CB: Garrett Williams > Denzel Burke (+2.26)
- QA-suspect BUF OLB: Shaq Thompson > Dorian Williams (+2.48)
- QA-suspect DAL CB: Shavon Revel Jr. > Reddy Steward (+3.21)
- QA-suspect DET CB: D.J. Reed > Rock Ya-Sin (+3.01)
- QA-suspect DET DE: Marcus Davenport > Al-Quadin Muhammad (+2.17)
- QA-suspect IND CB: Sauce Gardner > Mekhi Blackmon (+1.85)
- QA-suspect LA CB: Quentin Lake > Cobie Durant (+2.63)
- QA-suspect LAC LT: Bobby Hart > Austin Deculus (+2.85)
- QA-suspect LAC MLB: Marlowe Wax > Troy Dye (+2.44)
- QA-suspect LAC OLB: Khalil Mack > Odafe Oweh (+1.98)
- QA-suspect MIA RT: Austin Jackson > Larry Borom (+2.08)
- QA-suspect MIN RB: Aaron Jones > Jordan Mason (+1.98)
- QA-suspect NO C: Erik McCoy > Luke Fortner (+3.22)
- QA-suspect NO OLB: Jonah Williams > Carl Granderson (+3.21)
- QA-suspect NYJ CB: Tre Brown > Qwan'tez Stiggers (+1.94)
- QA-suspect PIT FS: DeShon Elliott > Chuck Clark (+2.72)
- QA-suspect SEA CB: Devon Witherspoon > Josh Jobe (+2.30)
- QA-suspect SEA FS: Julian Love > Ty Okada (+2.65)
- QA-suspect SF DE: Mykel Williams > Bryce Huff (+1.82)
- QA-suspect TB RB: Bucky Irving > Rachaad White (+1.84)
- QA-suspect WAS WR: Treylon Burks > Chris Moore (+1.92)
- QB starter lock: 2/32 rooms needed a lift so the snapshot's QB1 tops his room (QA_REPORT section 4.1)
- team-spread fixed point: max |team mean error| = 0.175 OVR
- blueprint anchor 71.01 OVR; global level shift +0.60 applied to match the random LeagueGenerator league mean
- jersey collision BUF #23: kept by the higher-rated player; Dane Jackson reassigned to #2
- jersey collision IND #17: kept by the higher-rated player; Philip Rivers reassigned to #3
- owners: 5 of 32 female (DET, IND, NO, SEA, TEN) — `identity.ownerGender` in BOTH profiles; the real NAME stays dev-only
- faces: 1902 pre-assigned per profile (1807 players + 95 coaches), 135 from the reserve range (face_02048+), 281 generated-range faces left for the career

