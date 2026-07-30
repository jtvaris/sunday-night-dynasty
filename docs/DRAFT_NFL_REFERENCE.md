# NFL Draft Reference Data (2016–2025) — Generator Calibration Targets

Purpose: ground-truth targets for Dynasty's draft class generator. All generator
distributions, clamps and guardrails must trace back to a number in this file.
Figures are 10-year (2016–2025) observations; `~` marks estimates reconstructed
from multiple sources rather than exact counts.

## 1. Draft structure

- 7 rounds, 32 base picks/round, + compensatory picks → **~257–262 total picks** (2025: 257).
- Teams also sign **~450 UDFAs** league-wide immediately after the draft; ~15–20 % of eventual NFL rosters are former UDFAs, but any individual UDFA's odds of becoming a starter are <5 %.
- NFL teams' internal boards typically carry only **15–25 "true first-round grades"** in a normal year — fewer than the 32 R1 picks. Round grades are scarce at the top by construction.

## 2. Positions drafted per class (share of all picks, 10-yr averages)

Normalized share of picks by position, with observed per-class count ranges
(out of ~257 picks). Use shares (not absolute counts) so any class size works.

| Position | Share of picks | Count avg | Count range | R1 avg | R1 range |
|---|---|---|---|---|---|
| QB | ~5.5 % | ~12 | 8–15 | 3.2 | **1–6** |
| RB (+FB) | ~9.5 % | ~21 | 17–27 | 1.4 | **0–3** |
| WR | ~14.0 % | ~32 | 25–36 (2024: 35) | 4.2 | 2–7 |
| TE | ~6.0 % | ~14 | 10–17 | 1.0 | 0–2 |
| OT | ~8.0 % | ~18 | 13–22 | 4.5 | 2–7 |
| IOL (G/C) | ~7.5 % | ~17 | 12–20 | 2.0 | 0–4 |
| EDGE | ~9.5 % | ~22 | 16–26 | 4.5 | 2–7 |
| DT | ~7.5 % | ~17 | 11–21 | 3.0 | 1–6 |
| LB (off-ball) | ~8.0 % | ~18 | 12–22 | 1.8 | 0–5 |
| CB | ~13.0 % | ~30 | 24–36 (2024: 36) | 4.5 | 2–7 |
| S | ~6.5 % | ~15 | 10–19 | 1.2 | **0–3** |
| K / P / LS | ~1.7 % | ~4 | 2–7 | 0 | 0 (never R1; earliest ever pick 59, typical 99+) |

**QB first-rounders by year (exact):** 2016: 3 · 2017: 3 · 2018: 5 · 2019: 3 ·
2020: 4 · 2021: 5 · 2022: **1** · 2023: 3 · 2024: **6** (most since 1983) · 2025: 2.
→ mean 3.5, hard range 1–6. **A class with 3 R1-grade QBs + 20 R2-grade QBs is
impossible**: the 10-yr max for QBs in the first two rounds is ~6–7 (2024: 6).

## 3. Round-band skew per position

Share of a position's drafted players landing in R1 / Day 2 (R2–3) / Day 3 (R4–7):

| Position | R1 | R2–3 | R4–7 | Character |
|---|---|---|---|---|
| QB | 28 % | 22 % | 50 % | top-heavy or barren; binary |
| RB | 7 % | 26 % | 67 % | day-2/3 position in the modern NFL |
| WR | 13 % | 30 % | 57 % | deep every year |
| TE | 7 % | 27 % | 66 % | rare elite, long tail |
| OT | 25 % | 30 % | 45 % | premium; tackles go early |
| IOL | 12 % | 30 % | 58 % | steady mid-round supply |
| EDGE | 20 % | 30 % | 50 % | premium |
| DT | 18 % | 28 % | 54 % | |
| LB | 10 % | 30 % | 60 % | devalued in R1 |
| CB | 15 % | 30 % | 55 % | premium + deep |
| S | 8 % | 30 % | 62 % | devalued in R1 |
| K/P/LS | 0 % | 4 % | 96 % | day-3 only |

## 4. "Best player at position" guardrails

Even in the weakest year for a position, its top prospect still goes early.
Earliest–latest **overall pick of the FIRST player drafted per position**, 2016–2025:

| Position | First player picked, range | Worst-case grade for a class's best prospect |
|---|---|---|
| QB | #1 – #20 (2022 Pickett) | Round 1 |
| RB | #2 – #46 (2024) | **Early round 2** |
| WR | #2 – #25 | Round 1 |
| TE | #4 – #55 (2022 McBride) | Round 2 |
| OT | #4 – #13 | Round 1 |
| IOL | ~#24 – #65 | Round 2–3 |
| EDGE | #1 – #16 | Round 1 |
| DT | #3 – #28 | Round 1 |
| LB | #8 – #45 (2024) | Round 2 |
| CB | #2 – #22 | Round 1 |
| S | #6 – #47 (2024 Nubin) | **Early round 2** |
| K/P | #59 (all-time outlier) – undrafted; typical #99–#200 | Round 4–7 |

→ Generator invariant: **the best RB or S of any class may never carry a grade
worse than round 2** (and the best QB/WR/OT/EDGE/CB/DT never worse than round 1
boundary, i.e. top-40 value). The user-reported bug ("best RB = round 5 grade")
violates a constraint that has held every single year in NFL history.

## 5. Combine measurables per position (mean ± SD, observed floor–ceiling)

40-yard dash (s): record 4.21 (Worthy 2024). WRs avg ~4.48–4.52, DBs ~4.53.

| Pos | 40 yd | Bench (reps) | Vert (in) | Broad (in) | 3-cone (s) | Shuttle (s) | Ht (in) | Wt (lb) |
|---|---|---|---|---|---|---|---|---|
| QB | 4.83 ± .12 (4.55–5.10) | — (skip) | 30.5 ± 3 | 112 ± 6 | 7.15 ± .20 | 4.40 ± .15 | 74.5 ± 1.5 | 222 ± 12 |
| RB | 4.52 ± .08 (4.32–4.75) | 20 ± 4 | 34.5 ± 3 | 119 ± 5 | 7.05 ± .15 | 4.30 ± .12 | 70.5 ± 1.5 | 213 ± 12 |
| WR | 4.49 ± .08 (4.22–4.70) | 13 ± 3 | 36 ± 3 | 122 ± 5 | 6.95 ± .15 | 4.25 ± .12 | 72.5 ± 2 | 200 ± 12 |
| TE | 4.72 ± .10 (4.55–5.00) | 21 ± 4 | 33 ± 3 | 116 ± 5 | 7.10 ± .15 | 4.40 ± .12 | 76.5 ± 1 | 251 ± 8 |
| OT | 5.16 ± .13 (4.85–5.45) | 24 ± 5 | 27.5 ± 3 | 103 ± 6 | 7.75 ± .25 | 4.80 ± .15 | 78 ± 1.2 | 315 ± 12 |
| IOL | 5.22 ± .12 (4.95–5.50) | 27 ± 5 | 28 ± 3 | 104 ± 6 | 7.70 ± .22 | 4.75 ± .15 | 75.5 ± 1.2 | 310 ± 12 |
| EDGE | 4.70 ± .10 (4.40–4.95) | 24 ± 4 | 33.5 ± 3.5 | 118 ± 6 | 7.15 ± .20 | 4.45 ± .13 | 75.5 ± 1.5 | 258 ± 12 |
| DT | 5.02 ± .14 (4.70–5.35) | 29 ± 5 | 29 ± 3.5 | 108 ± 7 | 7.60 ± .25 | 4.75 ± .15 | 74.5 ± 1.5 | 305 ± 15 |
| LB | 4.62 ± .09 (4.38–4.85) | 22 ± 4 | 34 ± 3 | 119 ± 5 | 7.10 ± .18 | 4.35 ± .12 | 73 ± 1.5 | 235 ± 8 |
| CB | 4.47 ± .07 (4.28–4.65) | 14 ± 3 | 36.5 ± 3 | 124 ± 5 | 6.90 ± .15 | 4.20 ± .10 | 71.5 ± 1.5 | 193 ± 8 |
| S | 4.53 ± .08 (4.35–4.72) | 16 ± 3 | 36 ± 3 | 122 ± 5 | 7.00 ± .15 | 4.25 ± .10 | 72 ± 1.5 | 205 ± 8 |
| K/P | 4.95 ± .15 | — | — | — | — | — | 73 ± 2 | 200 ± 15 |

Modeling rules:
- Sample from the position distribution **correlated r ≈ 0.75–0.9 with the
  underlying speed/strength/agility attributes** plus day-of noise; never a
  global range shared across positions.
- Truncate at the observed floor/ceiling; allow a **~0.5 % freak tail** (a
  4.2x WR, a 4.4 EDGE) that generates combine-riser headlines.
- Participation: ~25–40 % skip some drill (bench skipped most, esp. QB/WR;
  some stars run only at pro day). Skipping is informative UI flavor, not a penalty.
- Drill letter grades must be graded **relative to the position group**, and the
  top of each class should produce **a handful of A/A+ drills per position group**
  (1–3 elite testers per position per year), plus B-range bulk and C/D tail.

## 6. Career outcomes by draft slot (calibration for potential/bust tuning)

Primary-starter rates (≥1 season as primary starter, and 4+-yr starter for R3–7
per the 2000–2024 study):

| Round | Becomes primary starter | Long-term (4+ yr) starter | ≥1 Pro Bowl | Never contributes ("bust") |
|---|---|---|---|---|
| 1 (top 5) | ~83 % | ~65 % | ~45 % | ~17 % |
| 1 (all) | ~55–65 % | ~50 % | ~25–30 % | ~20–25 % |
| 2 | ~51 % | ~40 % | ~12–15 % | ~30 % |
| 3 | ~38 % | ~29 % | ~8 % | ~40 % |
| 4 | ~29 % | ~20 % | ~5 % | ~50 % |
| 5 | ~29 %* | ~15 % | ~4 % | ~60 % |
| 6 | ~19 % | ~9 % | ~3 % | ~70 % |
| 7 | ~14 % | ~6 % | ~2 % | ~78 % |
| UDFA | ~5 % | ~3 % | ~1 % | ~90 % |

*different metric definitions between studies; treat as ±5 pp bands, not exact.

Positional success in rounds 3–7 (2000–2024): OL 22 %, TE 21 %, DT 17.5 %,
DE 17.4 %, LB 16.4 %, DB 13.8 %, WR 10.5 %, QB 7.0 %, RB 6.8 %. → late-round
OL/TE outperform; late-round QB/RB rarely hit.

Elite outcomes are extremely rare outside the top: of ~3 700 players drafted in
rounds 3–7 (2000–2019), only ~0.5 % earned 2+ First-Team All-Pro selections.

## 7. Rookie-year contribution (why almost nobody contributes 100 % on day 1)

Typical rookie snap share / role by draft slot:

| Slot | Typical rookie role | Snap share |
|---|---|---|
| R1 | starter by mid-season, often day 1 | ~60–75 % |
| R2 | part-time starter / heavy rotation | ~45–55 % |
| R3 | rotation + special teams | ~30–40 % |
| R4–5 | depth + core special teams | ~15–25 % |
| R6–7 / UDFA | ST or practice squad | ~0–15 % |

Position speed-to-field (fastest → slowest to reach full effectiveness):
1. **RB, CB, OT** — can start day 1 (RB workloads immediate; CBs get thrown in).
2. **WR, EDGE, DT, IOL** — rotational year 1, typical **year-2 leap** (WR
   rookie production averages ~55–65 % of their year-3 level).
3. **LB, S, TE** — diagnosis/assignment-heavy; usually year 2 before trusted.
4. **QB, C** — steepest mental curve. Even R1 QBs who start day 1 perform well
   below their eventual level as rookies; classic jump is year 2–3.

Even elite rookies rarely play at 100 % of their talent: scheme install,
protection calls, NFL speed. Model as **low starting scheme familiarity +
mental-attribute-driven ramp**, not as a flat ratings penalty.

## 8. Development curve norms (phase-2 anchor, generator must stay consistent)

- Biggest growth: **year 1 → 2** (avg +8–12 % effectiveness), year 2 → 3 (+4–6 %), then plateau.
- Peak-age windows: RB 24–26 · CB 24–27 · LB 24–28 · WR 25–28 · EDGE 25–29 ·
  S 25–28 · DT 26–29 · TE 26–29 · OT/IOL 27–31 · QB 28–33 · K/P 28–35.
- Decline: speed positions lose ~2–4 %/yr after ~28 (RB earliest, ~27);
  QB/OL/K decline latest and slowest.
- Late bloomers exist but are rare (~5–10 % of hits are year-4+ breakouts, more
  common for OL/TE/QB) — development noise, coaching quality and opportunity
  should produce them organically.

## 9. Year-to-year positional strength (variance model)

Observed extremes prove strength varies, but **within bounds**:

- QB: 2022 (1 R1, first QB pick 20) vs 2024 (6 R1, three top-3) — strong and
  barren years both happen; never 0 R1-grade QBs, never >6–7 in two rounds.
- RB: 2017 (Fournette/McCaffrey/Cook/Mixon/Kamara/Hunt) & 2025 (Jeanty #6) vs
  2022/2024 (zero R1 RBs, first RB picks 36/46).
- WR: 2020 (6 R1) / 2024 (7 R1, three top-10) vs 2018–19 (2 R1).
- S: droughts 2021/2023/2024 (0 R1, first S in 43–47 range) vs 2017 (loaded).
- TE: 2021 (Pitts #4) vs 2022 (first TE #55).

Modeling: per class, draw a positional strength multiplier
`s_pos ~ Normal(1.0, 0.15)`, clamp to **[0.70, 1.35]** (QB/TE slightly wider σ
for boom/bust classes), apply to the position's round-band weights, then
**re-normalize and enforce §4 guardrails**. Strength should tilt how many
early-round prospects a position gets — it must never delete the position's top
end below round 2 or flood 20 same-position players into one band.

## 10. Sources

- [BetMGM — NFL draft R1 QBs by year](https://sports.betmgm.com/en/blog/nfl/nfl-draft-round-1-quarterbacks-by-year-bm16/); [The Injury Expertz — QBs drafted by round 2020–25](https://www.theinjuryexpertz.com/nfl-qbs-drafted-by-round/)
- [NFL.com — best/average 40 times by position](https://www.nfl.com/news/2026-nfl-combine-best-and-average-40-yard-dash-times-by-position); [PFN — combine records](https://www.profootballnetwork.com/nfl-combine-records-40-time-bench-press-vertical-jump-more/); [NBC LA — combine records](https://www.nbclosangeles.com/news/sports/nfl/nfl-scouting-combine-records-40-yard-dash-bench-press-vertical-broad-jump/3640091/)
- [The Hog Sty — odds of success for a draft pick, rounds 3–7, 2000–2024](https://www.thehogsty.com/2025/04/21/updated-the-odds-of-success-for-a-draft-pick-part-4/)
- [RotoWire — Pro Bowl/All-Pro/bust rates by pick slot](https://www.rotowire.com/football/article/nfl-draft-pick-value-analysis-105496); [PFF — positional hit rates](https://www.pff.com/news/draft-what-historical-hit-rates-reveal-about-positional-success); [Riot Report — R1 bust statistics](https://theriotreport.com/more-than-50-of-first-round-picks-are-busts-and-other-terrifying-draft-statistics/)
- [PFN — 2024 draft position counts (36 CB, 35 WR)](https://www.profootballnetwork.com/cornerbacks-drafted-in-2024-nfl-draft/); [Pro-Football-Reference — draft listings](https://www.pro-football-reference.com/draft/)
