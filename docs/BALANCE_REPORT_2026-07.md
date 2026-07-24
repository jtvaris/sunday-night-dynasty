# Balance Report — Full-Game & Systems (POST-FIX RE-ANALYSIS v2)

_Engine working tree at HEAD `4cc0c40` (branch `feat/skeletal-mocap-players`) **plus three uncommitted engine fixes** — `PlaySimulator.swift` `e628e77`, `DriveSimulator.swift` `352567c`, `LiveGameEngine.swift` `8a9c29d`. Report date 2026-07-24. v2 re-analyses the engine **after** the round-5 P0/P1 fixes landed; the original round-5 report is preserved verbatim as PART II below._

_v2 numbers are drawn from four post-fix re-sweep campaigns (A/B/C/D) **and** my own independent adjudication re-runs (N=1500, `--seedable --seed 777`) of every headline / disputed cell, run against the SHA-verified fixed working tree. Where two re-sweeps disagreed or a printed number was implausible, I re-ran that scenario myself and print my number as authoritative (adjudications called out inline)._

---

## Health Summary (CURRENT engine): **CONCERNS — substantially narrowed; ONE Medium item from HEALTHY**

The three round-5 **P0/P1 blockers are RESOLVED and independently re-confirmed:**

1. **Systemic passing/scoring inflation — FIXED at avg/good/elite.** avg-vs-avg points **33.0 → 19.9**, net-YPA **8.62 → 6.16**, 3rd-down **52.8% → 43.6%**, pass-yds **341 → 235**, total **453 → 346** — every round-5 hot-side violation is back in band. The efficiency ladder is now cleanly monotone weak→elite (see the good-good correction below).
2. **Talent curve too steep — FIXED.** elite-vs-weak went from **100.0% / +96.3 / max-139** (deterministic) to **93.9% / +15.7 / max-58** (never 100%); good-vs-avg **98.6% → 71.7%**. The whole mismatch ladder is monotone and correctly shaped, and single-unit discrimination survives intact (QB/CB position sweeps still monotone).
3. **Familiarity cliff — FIXED (committed at `4cc0c40`).** fam100-vs-33 at equal talent **~93% → 77.6%**; the convex low-end cliff (fam66-vs-33 88%) is gone (**64.7%**, monotone); the ~500-yd/game coverage leak is now +55/g. Familiarity now weighs ≈ one talent tier, not more.

**No structural break, no exploit-degenerate strategy, no dead attribute** — the play-choice layer (max within-family EV ratio 1.38) and all 9 position groups remain clean and monotone. The play-level FIXED BASELINE held on every anchor.

**What bars HEALTHY — one Medium regression the fixes introduced:**

- **(M) Weak-tier equal-game floor is now fully out of band.** P0-1's de-inflation is a roughly-**uniform ~−13-pt downshift**, so it pulled avg/good/elite into band but dropped weak-vs-weak **below the NFL floor on all six efficiency axes** (points 14.0, completion 51.5%, ypc 3.29, net-YPA 5.28, 3rd-down 34.2%, rush 94.1). Round-5 weak-weak was in band (26.5 pts). Playable, not exploitable — but a genuine band regression, and the single item gating the HEALTHY label.
- **(S) avg passing pinned at the band floor** — completion 59.5% (−0.5) and ypc 3.87 (edge) sit just below floor; avg points 19.9 land at the low end of 17-27. A mild COOL overcorrection, the opposite of and far preferable to round-5's hot-side breaks.
- **(S) avg-vs-weak one-tier runs +3 hot** (78.1% vs 75% ceiling) — an interaction of the wide weak band (real team-gap ~12.5 > good-vs-avg's ~9) with the underpowered weak tier. elite-vs-good is marginal (76.5%, +1.5).
- **(S) equal-tier efficiency SLOPE unchanged** — the compression is inert at gap=0, so "passing runs hot" is solved at avg but the slope is still steep: weak-weak cold ⇄ elite-elite hot (comp 69.0%, 3rd 53.9%). The weak-floor fix and this are the same knob.

**Verdict:** the engine is **not yet ship-ready-balanced**, but it is one bounded tuning pass away — taper the P0-1 de-inflation toward the weak band (raise the low-talent floor, which also flattens the equal-tier slope from both ends), then re-run the weak/avg/one-tier cells. Everything else is ship-adjacent.

---

## The Three Fixes (what / why / measured)

### P0-1 — full-game passing/scoring de-inflation _(uncommitted; `DriveSimulator.swift`, `LiveGameEngine.swift`, `PlaySimulator.swift`)_

- **What:** the sim path (`GameSimulator → DriveSimulator → PlaySimulator`) passed `defensivePackage: nil` on **every** snap, skipping the ~0.12 coverage tax the per-play bands are calibrated on. Fix adds `DriveSimulator.situationalDefensivePackage(...)` and wires it into the snap loop (`defensivePackage = situationalDefensivePackage(...) ?? .standard`); `LiveGameEngine.baseDefensivePackage()` is refactored to delegate to the **same shared brain** so the sim and coached paths can never drift. Situational shells: red-zone man/goal-line, late-lead prevent/dime, 3rd-&-long(≥7) cover4/dime, short-yardage(≤2) cover1/bear, else `.standard` (cover3/base); mean coverage ≈ 0.13. Secondary, FIXED-BASELINE-safe (forced-call probe bands bypass them): early-down pass-weight trim (0.55→0.50 / 0.50→0.42) and deep-share 24%→12%.
- **Why:** at avg talent the situational full-game AI was passing far more efficiently than the flat 45/40/15 per-play blend the bands are tuned on — the entire round-5 inflation was play-selection, not attributes.
- **Measured (avg-vs-avg, my re-run N=1500):** points 33.0→**19.9**, net-YPA 8.62→**6.16**, completion 67.5→**59.5**, 3rd-down 52.8→**43.6**, pass 341→**235**, total 453→**346**. All hot axes into band; completion/ypc slightly under-shoot the floor.

### P0-2 — talent-curve compression _(uncommitted; inside `PlaySimulator.swift`)_

- **What:** `edgeCompressionScale(...)` — a **monotone-decreasing smoothstep** on the team-aggregate overall gap `|mean(off) − mean(def)|`, computed once per snap as `edgeScale` and multiplied into every 0-centered talent channel. Constants `teamEdgeFull=3.5`, `teamEdgeCrush=9.0`, `teamEdgeFloor=0.085`: scale ≈1.0 for gap ≤3.5 (parity + single/dual-unit edges + per-play matrix cells), ramping to the floor by gap ≥9 (uniform-tier mismatch zone).
- **Why:** P0-1 de-inflated equal-talent scoring but barely dented the mismatch tail (elite-weak only +96.8→+86.0, ×0.89) — the whole mismatch fix rests on P0-2. Note the deliberate deviation from the trace's `softKnee`: softKnee is monotone-**increasing** and therefore structurally incapable of the required surface (≈0.9 at gap 3 to protect a shutdown-CB pair **and** ≈0.09 at gap 9 to crush a 1-tier roster); a decreasing ramp is mandatory.
- **Measured:** elite-vs-weak 100%/+96.3/max-139 → **93.9%/+15.7/max-58** (never 100%); good-vs-avg 98.6% → **71.7%**; ladder monotone (see below). Single-unit sweeps stay in the flat zone and remain monotone (QB 21.5→79.0%, CB 31.8→80.2%) — compression flattens **whole-roster** mismatches only, exactly as designed.

### P1 — familiarity cliff _(committed at `4cc0c40`)_

- **What:** cap the defensive coverage-bust **outcome** and compress the fam→effect curve at the low end.
- **Why:** round-5 fam33 defenses surrendered ~500 pass-yds / 10.5 net-YPA (bust term appeared uncapped), making a barely-installed scheme a ~93% automatic loss at equal talent, with a convex low-end cliff.
- **Measured (avg talent, my re-run):** fam100-vs-33 ~93% → **77.6%** (target 74.1, window 70-80); fam66-vs-33 (was convex 88% cliff) → **64.7%** (target 63.7); coverage leak ~500yd → **+55/g** (target +59). Monotone, no cliff; fam100-vs-33 ≈ one talent tier (elite-good 76.5%) — balanced, not over-weighted.

_(A fourth changed file, `tools/balance-harness/driver/main.swift`, is harness-side diagnostic only — no engine math.)_

---

## Headline Before → After (avg-vs-avg unless noted; round-5 → fixed)

| metric | round-5 (pre-fix) | **now (fixed)** | band | verdict |
|---|---|---|---|---|
| points/team | 33.0 ❌hi | **19.9** | 17–27 | ✅ FIXED (low end) |
| total yds | 452.6 ❌hi | **345.6** | 300–400 | ✅ FIXED |
| pass yds | 341.3 ❌hi | **234.6** | 200–250 | ✅ FIXED |
| rush yds | 111.3 ✅ | **111.0** | 100–130 | ✅ unchanged |
| plays | 67.2 ✅ | **66.8** | 58–68 | ✅ |
| sacks-taken | 2.48 ✅ | **2.98** | 2–3 | ✅ |
| INT thrown | 1.05 ✅ | **0.88** | 0.7–1.3 | ✅ |
| completion | 67.5 ❌hi | **59.5** | 60–67 | ⚠️ over-corrected −0.5 |
| ypc | 4.04 ✅ | **3.87** | 3.9–4.6 | ⚠️ slipped to edge −0.03 |
| net-YPA | 8.62 ❌hi | **6.16** | 5.9–7.5 | ✅ FIXED |
| 3rd-down | 52.8 ❌hi | **43.6** | 35–45 | ✅ FIXED |
| elite-vs-weak win% / margin | 100.0% / +96.3 ❌ | **93.9% / +15.7** | never 100 | ✅ FIXED |
| good-vs-avg win% | 98.6% ❌ | **71.7%** | 66–75 | ✅ FIXED |
| familiarity fam100-vs-33 | ~93% ❌ | **77.6%** | 70–80 | ✅ FIXED |
| max single-team score | 139 ❌ | **58** | — | ✅ absurd tails gone |

Six round-5 out-of-band violations closed; two new floor-edge under-shoots (completion, ypc) traded in — a mild cool overcorrection.

---

## My Independent Adjudication Re-Runs (fixed tree, N=1500, `--seed 777`)

SHA discipline: `sync_sources.sh` ran clean — 17 verbatim engine sources SHA byte-identical, 39 AI tuning lines byte-identical, SimPlayer/GameModels splices intact, MANIFEST records `PlaySimulator e628e77` / `DriveSimulator 352567c` == the fixed working-tree files. No stale-default drift.

| scenario re-run | re-sweep claim(s) | **my re-run** | verdict |
|---|---|---|---|
| avg-vs-avg full box | C 19.8 / D 19.9 pts; cmp 59.5; nYPA 6.2 | **19.9 pts, cmp 59.5, ypc 3.87, nYPA 6.16, 3rd 43.6** | **CONFIRMED** |
| **one-tier ladder (C vs D disagree)** | C: elite-good **80.0** hot, avg-weak 74.4 · D: avg-weak **79.3** hot, elite-good 75.5 | **good-avg 71.7 / elite-good 76.5 / avg-weak 78.1** | **ADJUDICATED → D correct: avg-weak is the hot rung; C's 80.0 elite-good was the outlier** |
| **good-good efficiency (C implausible)** | C: cmp **59.8** / ypc 3.90 / nYPA 6.25 / 3rd 43.6 (≈ avg-avg, breaks monotonicity) | **cmp 65.0 / ypc 4.30 / nYPA 6.80 / 3rd 49.1** | **CORRECTED — C's efficiency columns were a transcription dup of avg-avg; good-good is properly hotter** |
| two-tier ladder (C vs D disagree) | C: elite-avg 82.1 / good-weak 89.0 · D: 85.8 / 87.3 | **elite-avg 82.9 / good-weak 88.7** | **ADJUDICATED — both in 82–90 band, margins +10.8/+13.1** |
| elite-vs-weak (never-100 guard) | C 92.1–93.1 / D 93.8 | **93.9% / +15.7 / max-58** | **CONFIRMED — never 100** |
| weak-weak cold floor | C & D both ~14 pts, all axes cold | **14.0 pts, cmp 51.5, ypc 3.29, nYPA 5.28, 3rd 34.2, rush 94.1 — all OUT-lo** | **CONFIRMED regression** |
| familiarity fam100/66-vs-33 | C 76.2/63.5 · D 75.7/64.3 | **77.6% / 64.7%**, leak +55/g | **CONFIRMED — no cliff** |
| QB / CB position sweep | D QB 27→79.5, CB 33→74.5 (monotone) | **QB 21.5→79.0, CB 31.8→80.2 (monotone)** | **CONFIRMED — single-unit discrimination intact** |

### Definitive equal-tier ladder (my re-run — supersedes C's good-good row)

| tier | home-win% | margin | pts | cmp% | ypc | net-YPA | 3rd% | rush | read |
|---|---|---|---|---|---|---|---|---|---|
| weak-weak | 49.7% | +0.5 | 14.0 | 51.5 | 3.29 | 5.28 | 34.2 | 94.1 | ❌ COLD (all 6 axes OUT-lo) |
| avg-avg | 52.9% | +1.1 | 19.9 | 59.5 | 3.87 | 6.16 | 43.6 | 111.0 | ✅ on-target (cmp/ypc edge-lo) |
| good-good | 51.7% | +0.3 | 24.4 | **65.0** | **4.30** | **6.80** | **49.1** | 113 | ✅ pts/yds OK (3rd OUT-hi) |
| elite-elite | 55.3% | +1.8 | 28.0 | 69.0 | 4.72 | 7.32 | 53.9 | 136 | ❌ HOT (cmp/ypc/3rd OUT-hi) |

Cleanly monotone weak→elite on every axis (round-5's good-good row falsely read flat at avg-avg's numbers). The residual is the **slope**, not the shape: compression is inert at gap=0, so the weak-cold / elite-hot ends are un-flattened.

### Definitive mismatch ladder (my re-run)

| matchup | tiers apart | home-win% | margin | target | verdict |
|---|---|---|---|---|---|
| good-vs-avg | 1 | 71.7% | +6.7 | 66–75 | ✅ |
| elite-vs-good | 1 | 76.5% | +7.9 | 66–75 | ⚠️ +1.5 |
| avg-vs-weak | 1 | 78.1% | +8.2 | 66–75 | ⚠️ +3 hot |
| elite-vs-avg | 2 | 82.9% | +10.8 | 82–90, m10–20 | ✅ |
| good-vs-weak | 2 | 88.7% | +13.1 | 82–90, m10–20 | ✅ |
| elite-vs-weak | 3 | 93.9% | +15.7 | never 100 | ✅ |

Monotone in both win% and margin (1-tier 71.7/76.5/78.1 → 2-tier 82.9/88.7 → 3-tier 93.9). Never deterministic. The only overshoot is the wide-band one-tier avg-vs-weak (+3).

---

## Re-Sweep Result Sets (A / B / C / D)

### RE-SWEEP A — per-play-family × tier EV (play level) → **PASS (near-identity to round-5)**

The P0/P1 edits are structurally inert at the per-play layer by construction: named `offensiveCall` bypasses `decidePlayCall` (so P0-1 selection levers and P0-2 game-management never fire), and the probe pins every player `overall=70`, so `edgeScale` (keyed on team-avg overall gap = 0) returns 1.0 in every cell. Result: the calibrated per-play EV is **undisturbed**.

- **No dominant call:** max within-family EV ratio at equal talent = **1.38** (INSIDE @ weak, dive) — identical to round-5. Family ratios EDGE 1.01–1.05 / SHORT 1.21–1.24 / MID 1.08–1.09 / DEEP 1.07–1.08. Top-EV call per family unchanged (inside=dive, short=flat, mid=wheel, deep=flood).
- **Monotone:** all 28 calls rise weak→elite, zero zigzags, both independent runs. Max equal-tier per-cell drift vs round-5 = 0.19 net-YPA (MC noise at N=40k).
- **FIXED BASELINE guard (regression harness) — ALL IN BAND:** run 4.11 ypc / stuff 18.5%, depth 62.6/56.4/38.6 monotone, sack 8.7%, INT 2.22%, net-YPA 6.48, spam floor 1.89, deep tier matrix monotone both axes, keyed PA-deep 11.15.
- **Caveat for interpretation:** this near-identity confirms the fixes didn't perturb the per-play layer; it does **not** validate the P0-2 mismatch effect, which is invisible to an `overall`-pinned probe and must be read from the roster sweeps (B/C/D).

**Verdict A: PASS** — no dominant call, spreads monotone, no family changed at equal talent.

### RE-SWEEP B — position value curves (9 groups × {55,70,85,95}, N=4000/point) → **CLEAN / MONOTONE**

All 9 groups strictly monotone in win% and headline stat across both seeds — including **TE**, round-5's false "dead attribute" trip-wire, now cleanly monotone at N=4000 (48.1→60.2, +12.1 swing; the round-5 non-monotone read was N=400 noise). No dead groups.

| rank | group | round-5 swing | fixed swing | Δ | note |
|---|---|---|---|---|---|
| 1 | OL | 58.3 | 59.0 | +0.7 | steepest |
| 2 | QB | 55.2 | 56.0 | +0.8 | co-steepest |
| 3 | RB | 48.7 | **55.2** | **+6.5** | **rose #4→#3 into top cluster** |
| 4 | DL | 50.0 | 50.3 | +0.3 | — |
| 5 | CB | 46.9 | 46.6 | −0.3 | a tier below top cluster |
| 6 | S | 38.7 | 41.6 | +2.9 | — |
| 7 | WR | 32.2 | 35.8 | +3.6 | flat |
| 8 | LB | 23.3 | 23.7 | +0.4 | — |
| 9 | TE | ~1.6 (noise) | 12.1 | +10.5 | now cleanly monotone |

**Two round-5 positional skews are NOT resolved by curve compression (expected — P0-2 is not a per-position reweight):**
- **OL ≥ QB persists** (59.0 ≥ 56.0) — QB still not the sole steepest.
- **RB > WR widened** — gap +8.4 → **+19.4** (RB 55.2 vs WR 35.8). The NFL inversion is **worse**, an apparent side-effect of the P0-1 pass nerf lowering the marginal win-value of the pass-catch channel and steepening the run game. The expected "QB/OL/CB steepest cluster" verdict is corrected to **OL/QB/RB** (CB is #5).

g70 calibration point (home unit pinned to grade-70, marginally weaker than away's ~74.5 avg mean, so away-tilted by construction) reads points ~18–21, netYPA ~5.9, completion ~57–57.5 — consistent with the mild avg-completion under-shoot.

**Verdict B: PASS** on monotonicity + no-dead-groups; two carry-over positional-value skews (OL≈QB, RB>WR) remain open, RB>WR worsened.

### RE-SWEEP C — full games, fixed engine (N=800–1500) → **PASS (targets hit)**

avg-vs-avg into band on every axis (my re-run confirms 19.9 / 59.5 / 6.16 / 43.6); mismatch ladder monotone and never-100; asymmetric signatures preserved:
- **3a** elite-O/weak-D shootout — elite offense wins 86.4% (decisive, not deterministic).
- **3b** shutdown-CB pair — opposing elite-WR passYds 264→234, cmp 65.4→58.2, win 61.0→34.4% (−27pp): single-unit edge survives compression.
- **3c** elite-OL/weak-QB — runs more (rush 111→139, ypc 3.85→4.60), weak QB drags cmp 59.5→52.9; competitive 62.1%.

Familiarity (P1) holds at full game: fam100-vs-33 76.2%, fam66-vs-33 63.5% (cliff gone). Residual C flags: **weak-weak cold** and **elite-elite hot** — the equal-tier efficiency slope was not flattened (compression inert at gap=0). **Adjudication:** C's printed good-good efficiency row (cmp 59.8 / ypc 3.90 / nYPA 6.25) is a transcription duplicate of avg-avg and is superseded by my re-run (65.0 / 4.30 / 6.80); and C's one-tier elite-good 80.0 (hot) is superseded by my 76.5 (D's shape is correct).

**Verdict C: PASS** — both P0 fixes hit their full-game targets; residual = equal-tier efficiency slope (weak cold / elite hot).

### RE-SWEEP D — full games + systems (N=1200–1500) → **PASS with one new regression**

- **Play-level FIXED BASELINE — HOLD (all green):** run 4.10/stuff 18.5, depth 62/56/38, sack 8.72 (at edge ≤8.7), INT 2.26, net-YPA 6.43, keyed-PA 11.17–11.27, spam 1.90, deep matrix monotone (8.0× TD spread), RB×OL ordering 3.43<4.57<7.98, tier grids monotone both axes, CB scrub>shutdown, stacking worst-of-worst 1.55. The `edgeScale` multiplier preserves per-play sign/rank, so single/dual-unit anchors are byte-safe.
- **Talent ladder — HEALTHY / monotone** (matches my re-run within noise); away-favorite control (avg-H vs elite-A = 80% away) rules out home-tilt masking.
- **Band table — FIXED at avg** (points 33→19.9, netYPA 8.62→6.19, 3rd 52.8→43.6, pass 341→237 into band; completion 59.5 / ypc 3.89 at floor edge).
- **Familiarity (P1) — SURVIVES:** fam100-vs-33 75.7%, fam66-vs-33 64.3%, leak +56/g.
- **Adaptation — DIRECTION PASS, magnitude collapsed:** run-heavy win-penalty −9.4pp → ~0pp (points still pass 21.3 > bal 20.1 > run 19.1). A rational consequence of removing the pass inflation (no more opportunity cost) — removes the degenerate pass-skew meta (good) but "adaptation punishes run-heavy" is now a weak signal (design call).
- **Heat = variance-not-EV — PASS, minor caveat:** sd 9.5>9.4 (variance present), small +0.7pt EV lean marginally over the ±0.6 guard — unchanged from round-5, HeatState out of P0/P1 scope.
- **New regression (Medium):** weak-tier scoring floor fully out of band (weak-weak 14.3 pts / 51.7 cmp / 3.30 ypc / 5.31 nYPA / 34.6 3rd — all OUT-lo). The single item to fix before HEALTHY.

**Verdict D: PASS** on the P0/P1 targets and every play-level anchor; one new Medium regression (weak-tier floor) + minor floor-edge nits.

---

## Fresh Outliers Table (post-fix, ranked)

| # | outlier | evidence (my re-run unless noted) | severity | status |
|---|---|---|---|---|
| 1 | **Weak-tier equal-game floor out of band** | weak-weak all 6 axes OUT-lo: pts 14.0, cmp 51.5%, ypc 3.29, nYPA 5.28, 3rd 34.2%, rush 94.1 (round-5 was 26.5 pts, in band) | **M** | NEW regression from P0-1 uniform downshift — **blocks HEALTHY** |
| 2 | **Equal-tier efficiency slope too steep** | weak cold ⇄ elite-elite hot (cmp 69.0%, 3rd 53.9%, ypc 4.72); compression inert at gap=0 so slope un-flattened | S | pre-existing shape; same knob as #1 |
| 3 | **avg passing pinned at floor** | completion 59.5% (−0.5), ypc 3.87 (edge); points 19.9 at low end of 17–27 | S | mild cool overcorrection from P0-1 |
| 4 | **avg-vs-weak one-tier +3 hot** | 78.1% vs 75% ceiling; wide weak band (gap ~12.5) + underpowered weak tier; elite-good marginal 76.5% | S | interaction with #1 |
| 5 | **RB > WR positional inversion widened** | RB swing 55.2 vs WR 35.8, gap +8.4→+19.4 (Sweep B, N=4000) | S | side-effect of pass nerf; realism, not a break |
| 6 | **OL ≥ QB (QB not sole steepest)** | OL 59.0 ≥ QB 56.0 (Sweep B) | S | unchanged — P0-2 is not a position reweight |
| 7 | **run-heavy adaptation punishment neutralized** | −9.4pp → ~0pp win penalty (Sweep D) | S | design call — removes degenerate pass-skew meta (net good) |
| 8 | **Heat +EV lean** | macro Δmean +0.7pt, marginally over ±0.6 guard (Sweep D) | S | pre-existing, out of P0/P1 scope |
| — | Deep INT% high-but-monotone at low tier (~4.7%→1.8%) | Sweep A, borderline vs NFL deep ~3–4% | trivia | reproduces round-5, monotone |

---

## Final Verdict

**Balance health: CONCERNS → substantially narrowed. NOT ship-ready-balanced yet — gated on ONE Medium item.**

The three round-5 blockers (passing/scoring inflation, deterministic talent curve, familiarity cliff) are **resolved and independently re-confirmed** at the SHA-verified fixed working tree. The play-level FIXED BASELINE held on every anchor; the mismatch ladder is monotone and never deterministic; single-unit and position discrimination survive the compression; no dominant call, no dead attribute, no exploit-degenerate strategy.

**Precisely what still bars HEALTHY:**

- **(M, blocker) Weak-tier equal-game floor** — P0-1's ~uniform −13-pt de-inflation over-applies at low talent, dropping weak-vs-weak below the NFL floor on all six efficiency axes. Fix: **taper the P0-1 de-inflation toward the weak band** (raise the low-talent scoring/completion/run floor); this same change flattens the equal-tier efficiency slope, which also relaxes the symmetric elite-elite hot tail (#2). Re-run weak / avg / one-tier cells after.
- **(S, non-blocking) avg completion/ypc at floor** (nudge the pass-efficiency knob a hair warmer — folds into the weak-floor pass); **avg-vs-weak one-tier +3 hot** (largely resolves once the weak tier is lifted).

Everything else on the follow-up list is realism-tuning or out-of-scope, not a balance break: the carry-over positional skews (**RB>WR** widened — re-prioritize; **OL≈QB**), the neutralized run-heavy adaptation penalty (a net-positive side-effect), and the small heat +EV lean.

**Ship-readiness: one bounded tuning pass away.** Land the weak-tier floor taper, re-run Sweeps C/D on the weak and avg cells, and the engine clears to HEALTHY. The two P0 fixes and the P1 fix are sound and should be committed; the weak-floor taper is the only balance work remaining before this branch is shippable.

---
---

# PART II — ORIGINAL ROUND-5 REPORT (historical, pre-fix)

_Preserved verbatim. This was the pre-fix analysis (engine HEAD `4aa54d3`) that motivated the P0-1 / P0-2 / P1 fixes re-analyzed in v2 above. Its Health Summary (**CONCERNS**, four axes out of band) describes the engine **before** the fixes and is superseded by PART I._

## Data Sources Analyzed

Four Monte-Carlo sweep campaigns run through `tools/balance-harness/` against the **shipped** engine (`PlaySimulator → DriveSimulator → GameSimulator`, engine's own `BoxScore` output):

- **Sweep A — per-play EV** — `/tmp/round5/sweepA/` (`sweepA_results.txt`, `VERDICTS.md`, `probe.swift`, stability re-run `sweepA_run2.txt`). 28 play calls × 4 tiers × 6 parity columns, N=40 000/cell, neutral 1st-and-10/own-25, UNKEYED (raw per-call talent EV, no PlayMemory).
- **Sweep B — position value** — `/tmp/round5/sweepB/` (`RESULTS.txt` + per-group raw). 9 position groups swept {g55,g70,g85,g95} on an avg roster vs avg opponent; avg of seed=default (N=400) and seed=777 (N=500).
- **Sweep C — full-game campaign** — `/tmp/round5/sweepC/` (`TABLES.txt` + per-scenario raw + `parse_side.py`). Complete games via the shipped pipeline; equal-tier + mismatch + asymmetric-unit scenarios, N=300–500/scenario, `--seedable` rosters, stochastic play RNG.
- **Sweep D — adaptation / familiarity / heat** — `/tmp/round5/sweepd/` (`RESULTS.md` + `raw/`). System-delta campaigns at avg tier, N=1000, seed 777.

### Independent adjudication re-runs (round-5 report)

Ran `sync_sources.sh` clean at HEAD `4aa54d3` — all 17 verbatim engine sources SHA-verified byte-identical, AdaptiveOpponentAIExtract's **39 tuning lines** verified byte-identical to the repo, SimPlayer/GameModels splices intact. No stale-default drift (the incident the harness was built to prevent). Then re-ran the five highest-impact / most-implausible numbers to adjudicate before printing them (results in the table below).

| Scenario re-run | Sweep claim | My independent re-run | Verdict |
|---|---|---|---|
| avg-avg full game (N=500) | pts 33.0 / nYPA 8.62 / cmp 67.5 / 3rd 52.8 (Sweep C) | **pts 32.9 / nYPA 8.64 / cmp 67.9 / 3rd 52.9** | **CONFIRMED** |
| elite(H)-vs-weak(A) (N=500) | home 100% / margin +96.3 / max 139 (Sweep C) | **home 100.0% / margin +96.6 / max 136** | **CONFIRMED deterministic** |
| OL vs QB steepest (N=500) | OL swing 58.3 ≥ QB 55.2 (Sweep B) | **OL swing 62.6 > QB swing 53.6** | **CONFIRMED — QB not sole steepest** |
| familiarity fam100(H)-vs-fam33(A) (N=500) | home 94.1% / margin +28.6 (Sweep D) | **home 93.2% / margin +27.0**; gradient fam66-vs-33 = **87.6%** | **CONFIRMED near-deterministic cliff** |
| TE "dead attribute" trip-wire (N=1500 ×2 seeds) | non-monotone 55.8/48.8/55.8/54.2, swing **+1.6**, "dead=bug" (Sweep B) | **monotone** 48.1/52.6/58.3/60.1 and 50.3/52.7/59.2/60.2, swing **~+11** | **CORRECTED — live but weakest; trip-wire does NOT fire** |

## Health Summary: **CONCERNS** _(pre-fix)_

The **core play-choice layer is HEALTHY** — Sweep A finds no dominant call at any parity (max within-family EV ratio 1.38, all 28 calls monotone across tiers). Position discrimination is clean and monotone for all 9 groups. No exploitable degenerate strategy exists.

But **four calibration axes are meaningfully out of band**, two of them at the CRITICAL threshold:

1. **Systemic passing/scoring inflation at every tier** (Sweep C) — points, total-yds, pass-yds, net-YPA and 3rd-down% are `[OUT]` high even at the engine's own avg calibration point (independently re-confirmed). Root cause is full-game situational play-selection, not attributes.
2. **Talent curve too steep at the extremes** (Sweep C) — elite-vs-weak is **100% deterministic** (re-confirmed), good-vs-avg is **98.6%**, both past the "biggest NFL favorites ~85–90%, never deterministic" guardrail.
3. **Familiarity over-punishes** (Sweep D) — fam100 beats fam33 at **equal talent** ~93% (re-confirmed), a near-deterministic cliff driven by an apparently-uncapped defensive coverage-bust term.
4. **Positional-value skews** (Sweep B, adjudicated) — OL ≥ QB (QB not the sole steepest), RB out-values WR (inverts NFL), TE is the lowest-value group (but live, not dead).

Nothing is broken or exploit-degenerate; the issues are tuning/calibration. Health is **CONCERNS** with items #1 and #2 sitting at the CRITICAL edge.

## Campaign Methodology

- **Harness:** `tools/balance-harness/run.sh` compiles the shipped simulation math with `swiftc -O` outside the iOS app and runs Monte-Carlo scenarios reading the engine's own `BoxScore`. It never touches `dynasty/dynasty/**`.
- **SHA discipline (mandatory, re-verified for this report):** every `run.sh` first runs `sync_sources.sh`, which copies 17 engine sources **verbatim** and asserts `sha(copy)==sha(repo)` for each, **regenerates** the adaptive-AI extract and fails the build if any of 39 tuning lines differ, and splices SimPlayer/GameModels drift-proof. A single mismatch aborts the build. This exists because rounds 2–3 shipped wrong numbers off a hand-copied shim that had silently drifted (`paKeyCompletion` 0.18 vs real 0.035). I recomputed the sync clean at HEAD `4aa54d3` before every re-run below.
- **Sample sizes / RNG:** per-play cells N=40 000; full-game campaigns N=300–1500. `--seedable` fixes **roster** draws (SplitMix64); the engine's play-by-play uses Swift's global **unseeded** RNG, so every game carries Monte-Carlo noise (±~0.1 ypc, ±~0.5pt comp%) — which is why shallow-signal metrics (e.g. TE win%) require large N to read. Throughput ~600 games/sec.
- **Tier bands:** elite 88–95, good 80–87, avg 70–79, weak 55–69. Per-play tiers use band midpoints (weak 62 / avg 74 / good 83 / elite 91).

## Full-Game Stat Table vs NFL Bands (Sweep C, equal-tier, per-team-per-game)

NFL reference bands per team per game: points **17–27**, total **300–400**, pass **200–250**, rush **100–130**, plays **58–68**, sacks-taken **2–3**, INT thrown **0.7–1.3**, completion **60–67%**, ypc **3.9–4.6**, net-YPA **5.9–7.5**, 3rd-down **35–45%**.

| tier | pts | total | pass | rush | plays | sacks | INT | cmp% | ypc | netYPA | 3rd% |
|---|---|---|---|---|---|---|---|---|---|---|---|
| weak-weak | 26.5 ✅ | 412.5 ❌ | 320.9 ❌ | 91.6 ❌lo | 68.0 ❌ | 2.67 ✅ | 0.64 ❌lo | 61.6 ✅ | 3.37 ❌lo | 7.87 ❌ | 45.6 ❌ |
| **avg-avg** | **33.0 ❌** | **452.6 ❌** | **341.3 ❌** | 111.3 ✅ | 67.2 ✅ | 2.48 ✅ | 1.05 ✅ | **67.5 ❌** | 4.04 ✅ | **8.62 ❌** | **52.8 ❌** |
| _avg-avg (my re-run)_ | _32.9_ | _452.1_ | _342.9_ | _109.2_ | _67.0_ | _2.61_ | _0.99_ | _67.9_ | _4.00_ | _8.64_ | _52.9_ |
| good-good | 36.5 ❌ | 477.7 ❌ | 353.2 ❌ | 124.6 ✅ | 66.5 ✅ | 2.38 ✅ | 1.25 ✅ | 71.0 ❌ | 4.48 ✅ | 9.13 ❌ | 56.7 ❌ |
| elite-elite | 39.8 ❌ | 503.3 ❌ | 363.2 ❌ | 140.1 ❌hi | 66.6 ✅ | 2.25 ✅ | 1.55 ❌hi | 72.7 ❌ | 4.99 ❌hi | 9.42 ❌ | 59.3 ❌ |

**Read:** passing (pass-yds, net-YPA, completion) and its downstream (points, total-yds, 3rd-down) are `[OUT]` high at **every** tier, monotone with talent. Rush/plays/sacks/INT/ypc mostly land in band. The avg tier — the engine's own calibration point, attribute-identical to the rosters the per-play bands are tuned on — is hot, so the gap is **play-selection**, not attributes (the situational full-game AI passes more efficiently than the flat 45/40/15 per-play blend). Independently re-confirmed within ±0.3 on every field. The weak tier additionally has an **underpowered run game** (rush 91.6, ypc 3.37 low) — the run/pass split skews pass-heavy at low talent.

**Score distribution / tails:** no 0-0 games occurred (lone weak-weak tie was 27-27; one-team shutouts ~0.4%). But single-team "burgers" reach 61 (weak) / 70 (avg/good) / 73 (elite) even at equal tier, and up to **139** in elite-vs-weak.

**Mismatch scaling:**

| matchup | home pts | away pts | home win% | margin | vs guardrail |
|---|---|---|---|---|---|
| elite(H) vs weak(A) | 100.5 | 4.2 | **100.0%** | +96.3 | ❌ deterministic (target ~85–90%, never 100%) |
| good(H) vs avg(A) | 57.5 | 17.2 | **98.6%** | +40.3 | ❌ (target 80–92%) |

Re-confirmed: elite-vs-weak 100.0% / +96.6 / max 136. Ordering is correct and monotone but scales far faster than NFL at the extremes. (Caveat: uniform tiers are an artificial construction — a realistic star/role-player mix narrows it.)

**Asymmetric-unit signatures (all PASS — believable):** (3a) elite-O/weak-D is a shootout the elite offense wins 75.7%, not all; (3b) a shutdown-CB pair suppresses elite WRs (pass 374→321, cmp 72→66%, netYPA 9.85→8.33, away pts 36.6→28.8) and flips ~24pp of win prob (away 59%→35%); (3c) elite-OL/weak-QB runs more and protects better (rush 116→166, ypc 4.05→5.52, sacks 2.54→0.79) while the weak QB drags accuracy/TOs (cmp 68.5→60.7, INT 1.01→1.75), netting a competitive 52.7% — "runs more, wins some" confirmed.

## Position-Value Ranking (Sweep B, adjudicated)

Ranked by win%-per-40-grade swing (g55→g95). "My re-run" column shows independently re-run swings where I re-checked; others are Sweep B's two-seed average against the SHA-verified harness.

| rank | group | Sweep B swing | my re-run swing | cluster | NFL-intuition check |
|---|---|---|---|---|---|
| 1 | **OL** | 58.3 | **62.6** | co-steepest | ⚠️ ties/edges QB — QB expected to be sole steepest |
| 2 | **QB** | 55.2 | **53.6** | co-steepest | ⚠️ not the sole steepest |
| 3 | DL | 50.0 | — | meaningful | ✅ |
| 4 | **RB** | 48.7 | **43.8** | meaningful | ⚠️ over-values WR (NFL: RB is low-tier) |
| 5 | CB | 46.9 | — | meaningful | ✅ |
| 6 | S | 38.7 | — | mid | ⚠️ slightly high, out-values WR |
| 7 | **WR** | 32.2 | **35.4** | low | ⚠️ under-valued; saturates at top (66→74% while passYds keep climbing) |
| 8 | LB | 23.3 | — | low | ✅ modest |
| 9 | **TE** | 1.6 (non-mono) | **~11 (monotone)** | lowest | ⚠️ **NOT dead** — Sweep B's non-monotone read was N=400 noise |

**Discrimination is clean:** at N≥1500 all 9 groups are monotone in both win% and headline stat. Parity at g70 sits ~48–52% (slight engine home tilt). Ceilings top ~76–83% home win for a single elite unit — decisive, never deterministic. **No group is absurdly dominant.**

**Three tuning skews (all adjudicated by re-run):**
1. **QB is not the sole steepest** — OL matches/edges it in every sample (my re-run: OL 62.6 > QB 53.6). Both drive HOME points up (22→43) with away flat, directionally correct, but NFL intuition (QB >> OL) does not hold.
2. **RB over-values WR** — RB win-swing (43.8) exceeds WR (35.4) in my re-run, driven by a very steep ypc response (2.45→5.86) and rush yards 62→172. NFL positional value puts RB in the low tier and WR far above it; the engine inverts this.
3. **TE is the lowest-value group but LIVE, not dead** — this is the one place I overturn a sweep. Sweep B flagged TE as the "dead attribute = bug" trip-wire (non-monotone, swing +1.6). At N=1500 across two seeds TE is **cleanly monotone** with a **~+11 win swing** (50→60%); the non-monotone read was a small-N Monte-Carlo artifact. TE's headline stat still moves least of the nine (cmp +3.8pp, passYds +33 over 40 grades vs WR's +12/+115), so TE win-value is **compressed** (defensible for the position, but the flattest of the pack) — a soft tuning note, **not** a bug.

## Per-Play EV — Play-Choice Balance (Sweep A)

**No dominant call at any parity.** Max within-family EV ratio (best/worst call) across all 4 equal-talent tiers = **1.38** (inside runs @ weak, dive/draw); every family/tier < 1.4 (edge 1.01–1.03, short 1.19–1.24, mid 1.08–1.09, deep 1.05–1.08). Top-EV call per family is stable across tiers (inside=dive, edge≈flat-tie, short=flat, mid=wheel, deep=flood). Favorable mismatch (ELITEoff/weakDEF) also balanced (max 1.18). All 28 calls rise **monotonically** weak→elite with zero zigzags. Stable on independent re-sample (±0.02).

**Localizes the "passing runs hot" finding to the play level:** equal-tier per-call mid-pass net-YPA is 9.3–11.1 and deep/PA 9.2–10.4 at good/elite, exceeding the full-game net-YPA band (5.9–7.5); even avg=avg mid/deep ~8.7–9.1 > 7.5. The steep offense-favoring monotone rise is present at the raw per-call layer, before any full-game play-selection compounding.

**Extreme-mismatch run-collapse artifact:** at weakOFF/ELITEdef (62/91) the run game collapses to a near-zero floor (best inside dive 2.22 ypc, edge outsideRun 0.56 / jetSweep 0.07 ypc at 77% stuff), blowing the within-family EV ratio to 2.26 (inside) / 7.80 (edge). This is a **small-denominator artifact** of the talent curve being too steep at extremes (corroborates Sweep C's finding #2), **not** a genuinely dominant call — every run option there is bad. Reproduces on independent sample.

## Degenerate Strategies Found

No hard-degenerate (strictly-dominant, exploit-breaking) strategy exists — the per-play layer is clean. Three **soft** degenerate leans, all downstream of the two systemic issues:

- **"Just pass more."** Symmetric play-style ladder: run-heavy **29.4** < balanced **32.4** < pass-heavy **35.8** pts/g; run-heavy loses **−9.4pp** win rate vs balanced (Sweep D). The mechanism (opportunity cost of foregoing the hot pass) is healthy, but the pass-favoring tilt is a direct consequence of the systemic passing inflation — the optimal meta is pass-skew, not balance.
- **Familiarity as a near-auto-win lever.** At equal talent, fam100 vs fam33 wins ~93% (re-confirmed 93.2%), 66% of games 3-score blowouts. Rushing your own scheme install or catching an opponent at low familiarity is worth more than a full talent tier — a lever strong enough to distort roster/scheme decisions.
- **Weak-tier pass-skew.** At the weak tier the run game is underpowered (ypc 3.37, rush 91.6) while passing stays hot, so even at low talent the correct call distribution over-indexes on passing.

None is exploit-breaking, but all three reward the same behavior (pass, and maximize familiarity) more than a balanced NFL meta would.

## Systems Verdicts (Sweep D — adaptation / familiarity / heat)

- **Adaptation (run-heavy vs balanced): PASS.** Run-heavy correctly **loses** (45.2% vs 54.5% net win, −9.4pp). Mechanism is opportunity cost, not a dramatic rush collapse — run-heavy actually gains rush volume (127 vs 108 yd) at slightly lower efficiency (ypc 3.98 vs 4.03). RunKeyState/PlayMemory per-carry punishment is mild in full games (ypc 4.02→3.96 when keyed) because play-type varies; the net anti-run-heavy outcome is correct and non-degenerate. **Direction right, magnitude healthy.**
- **Familiarity: DIRECTION PASS, MAGNITUDE FAIL (over-punishes).** fam100 beats fam33 **92.7%** net (+28.6 margin) at equal talent — re-confirmed 93.2% / +27.0 — past the 85–90% guardrail, rivaling the uniform elite-vs-weak talent extreme. Carried by passing: the fam33 **defense** surrenders ~500 pass-yds/g and 10.5 net-YPA (coverage-bust term appears **uncapped**), while the fam33 offense's own passing collapses to 52.8% cmp / 6.28 net-YPA. Gradient is **convex** (fam66-vs-33 = 88.0%, re-confirmed 87.6% > fam100-vs-66 = 70.8%), so fam~33 is a **cliff**. A barely-installed scheme should not be a ~93% automatic loss giving up 500+ pass yards.
- **Heat = variance, not free EV: PASS with a minor caveat.** EV-neutral at game grain (sensitive 32.5 vs immune 32.4 mean pts) and higher variance for sensitive rosters (score sd 10.8 vs 10.6; drive-level 10.1 vs 9.4; blowout +1.8pp). **Caveat/flag:** heat carries a **small net-positive EV bias** — macro Δmean +0.34 (N=400) to **+0.83** (N=2000, above the ±0.6 guard); over 12 000 drives Δcmp **+0.97pp** and Δypc **+0.13**, both breaching the harness's own non-inflation tolerance. Cause: asymmetric magnitude (hot +3.8pp cmp / +0.31 ypc exceeds cold −3.0pp / −0.16) plus success-feeds-heat feedback, so a ~0-mean process nets slightly positive. ~85% variance, ~15% EV lean. Streaks are well-formed (+0.34/success, clamp +1.0 after ~3, ×0.80/drive decay) but low-visibility in box scores (damped by ~130-play aggregation).

## Progression / Talent-Value Analysis

**Equal-tier scaling is not talent-neutral — it is steeply offense-favoring.** Every one of the 28 per-call EVs rises monotonically weak→elite (insideRun +40%, curl +43%, short comp 57→75%), and full-game points climb 26.5→33.0→36.5→39.8 weak→elite. So mutual talent raises efficiency (especially passing) rather than cancelling out. Combined with the mismatch curve (good-vs-avg 98.6%, elite-vs-weak 100%), the **talent→outcome curve is convex and too steep**: one tier of separation is nearly decisive, two tiers is deterministic. NFL talent gaps compress far more.

**Home-field tilt grows with tier** (minor): 48/52/54/57% home weak→elite (Sweep C). My avg-avg re-run landed 58% home (vs Sweep C's reported 51.6%) — the win-split % carries seed/Monte-Carlo noise (margin means differ <2pt on sd-17), so treat the exact per-tier home% as **low-confidence**; the directional "tilt grows with tier, slight over-tilt at good/elite" holds, the precise numbers do not.

## Recommendations _(round-5; superseded by the v2 fixes above)_

| Priority | Issue | Suggested Fix | Impact |
|---|---|---|---|
| **P0** | Systemic passing/scoring inflation at every tier (avg net-YPA 8.6, points 33, 3rd-down 53% — all OUT; re-confirmed) | Damp the full-game situational play-selection's pass efficiency toward the calibrated 45/40/15 per-play blend; pull net-YPA down ~1.3 and 3rd-down ~8pp at avg | Highest — inflates every downstream stat and drives the pass-skew meta |
| **P0** | Talent curve too steep at extremes (elite-vs-weak 100% deterministic, good-vs-avg 98.6%; re-confirmed) | Compress the talent→per-play-EV response (softer high end / raise low-tier floor) so one tier ≈ 65–75% and two tiers ≈ 85–90%, never 100% | Highest — breaks the "never deterministic" guardrail; unrealistic blowouts |
| **P1** | Familiarity over-punishes (fam100-vs-33 ~93% at equal talent; convex low-end cliff; re-confirmed) | **Cap the defensive coverage-bust penalty** (currently allows ~500 pass-yds/10.5 net-YPA) and compress the fam→effect curve at the low end so fam~33 is not a cliff | High — a scheme lever out-weighs a full talent tier |
| **P1** | TE win-value compressed / lowest of nine (adjudicated: live & monotone ~+11, not the "dead" bug Sweep B reported) | Verify TE target share / attribute weighting is intended; if TE should matter more, raise TE target share modestly. **Do not treat as a dead-attribute bug** | Medium — TE contributes ~⅓ of WR's win-value |
| **P2** | RB out-values WR (inverts NFL: RB swing 43.8 > WR 35.4) | Soften RB's ypc→win response and/or raise WR's ceiling (WR win% saturates while passYds keep climbing) | Medium — positional-value realism |
| **P2** | QB not the sole steepest (OL ≥ QB; re-confirmed OL 62.6 > QB 53.6) | Design call: either accept OL≈QB, or nudge QB's win-response above OL to match NFL intuition | Low–Medium — realism, not a break |
| **P3** | Heat carries a small net-positive EV bias (breaches ±0.6 guard) | Symmetrize the hot/cold magnitude (equal ± response) so heat is pure variance | Low — ~15% EV lean on an intended-neutral system |
| **P3** | Weak-tier run game underpowered (ypc 3.37, rush 91.6 low) | Raise the low-tier run floor (ties into the P0 curve-compression) | Low — narrow-band, low-talent only |

## Final League-Health Verdict _(round-5, pre-fix)_

**CONCERNS — playable and internally consistent, not shippable-balanced yet.** The foundation is sound: no dominant play call (max within-family EV ratio 1.38), clean monotone position discrimination across all 9 groups, believable asymmetric-unit signatures, and adaptation/heat systems that behave as intended. Independent re-runs at HEAD `4aa54d3` (SHA-verified, no drift) reproduced every headline number to within Monte-Carlo noise, and **overturned one sweep claim** — TE is a live, monotone, lowest-value position, **not** the "dead-attribute" bug Sweep B reported.

The blockers are two **P0 calibration** issues — systemic passing/scoring inflation at every tier, and an over-steep talent curve that makes one-tier gaps near-decisive and two-tier gaps deterministic — plus a **P1** familiarity term that over-punishes to near-determinism. All three are tuning problems in situational play-selection and talent/familiarity response curves, not structural breaks or exploitable degeneracies. Fix the two P0 curves and cap the familiarity bust term and the league moves from **CONCERNS** to **HEALTHY**.
