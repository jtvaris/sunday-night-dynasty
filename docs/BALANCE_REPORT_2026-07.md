# Balance Check: Round-5 Full-Game & Systems Sweep

_Engine HEAD `4aa54d3` (branch `feat/skeletal-mocap-players`, rounds 1–4 committed, tree clean). Report date 2026-07-24. Synthesized from four sweep campaigns (A/B/C/D) plus independent adjudication re-runs._

---

## Data Sources Analyzed

Four Monte-Carlo sweep campaigns run through `tools/balance-harness/` against the **shipped** engine (`PlaySimulator → DriveSimulator → GameSimulator`, engine's own `BoxScore` output):

- **Sweep A — per-play EV** — `/tmp/round5/sweepA/` (`sweepA_results.txt`, `VERDICTS.md`, `probe.swift`, stability re-run `sweepA_run2.txt`). 28 play calls × 4 tiers × 6 parity columns, N=40 000/cell, neutral 1st-and-10/own-25, UNKEYED (raw per-call talent EV, no PlayMemory).
- **Sweep B — position value** — `/tmp/round5/sweepB/` (`RESULTS.txt` + per-group raw). 9 position groups swept {g55,g70,g85,g95} on an avg roster vs avg opponent; avg of seed=default (N=400) and seed=777 (N=500).
- **Sweep C — full-game campaign** — `/tmp/round5/sweepC/` (`TABLES.txt` + per-scenario raw + `parse_side.py`). Complete games via the shipped pipeline; equal-tier + mismatch + asymmetric-unit scenarios, N=300–500/scenario, `--seedable` rosters, stochastic play RNG.
- **Sweep D — adaptation / familiarity / heat** — `/tmp/round5/sweepd/` (`RESULTS.md` + `raw/`). System-delta campaigns at avg tier, N=1000, seed 777.

### Independent adjudication re-runs (this report)

Ran `sync_sources.sh` clean at HEAD `4aa54d3` — all 17 verbatim engine sources SHA-verified byte-identical, AdaptiveOpponentAIExtract's **39 tuning lines** verified byte-identical to the repo, SimPlayer/GameModels splices intact. No stale-default drift (the incident the harness was built to prevent). Then re-ran the five highest-impact / most-implausible numbers to adjudicate before printing them (results in the table below).

| Scenario re-run | Sweep claim | My independent re-run | Verdict |
|---|---|---|---|
| avg-avg full game (N=500) | pts 33.0 / nYPA 8.62 / cmp 67.5 / 3rd 52.8 (Sweep C) | **pts 32.9 / nYPA 8.64 / cmp 67.9 / 3rd 52.9** | **CONFIRMED** |
| elite(H)-vs-weak(A) (N=500) | home 100% / margin +96.3 / max 139 (Sweep C) | **home 100.0% / margin +96.6 / max 136** | **CONFIRMED deterministic** |
| OL vs QB steepest (N=500) | OL swing 58.3 ≥ QB 55.2 (Sweep B) | **OL swing 62.6 > QB swing 53.6** | **CONFIRMED — QB not sole steepest** |
| familiarity fam100(H)-vs-fam33(A) (N=500) | home 94.1% / margin +28.6 (Sweep D) | **home 93.2% / margin +27.0**; gradient fam66-vs-33 = **87.6%** | **CONFIRMED near-deterministic cliff** |
| TE "dead attribute" trip-wire (N=1500 ×2 seeds) | non-monotone 55.8/48.8/55.8/54.2, swing **+1.6**, "dead=bug" (Sweep B) | **monotone** 48.1/52.6/58.3/60.1 and 50.3/52.7/59.2/60.2, swing **~+11** | **CORRECTED — live but weakest; trip-wire does NOT fire** |

---

## Health Summary: **CONCERNS**

The **core play-choice layer is HEALTHY** — Sweep A finds no dominant call at any parity (max within-family EV ratio 1.38, all 28 calls monotone across tiers). Position discrimination is clean and monotone for all 9 groups. No exploitable degenerate strategy exists.

But **four calibration axes are meaningfully out of band**, two of them at the CRITICAL threshold:

1. **Systemic passing/scoring inflation at every tier** (Sweep C) — points, total-yds, pass-yds, net-YPA and 3rd-down% are `[OUT]` high even at the engine's own avg calibration point (independently re-confirmed). Root cause is full-game situational play-selection, not attributes.
2. **Talent curve too steep at the extremes** (Sweep C) — elite-vs-weak is **100% deterministic** (re-confirmed), good-vs-avg is **98.6%**, both past the "biggest NFL favorites ~85–90%, never deterministic" guardrail.
3. **Familiarity over-punishes** (Sweep D) — fam100 beats fam33 at **equal talent** ~93% (re-confirmed), a near-deterministic cliff driven by an apparently-uncapped defensive coverage-bust term.
4. **Positional-value skews** (Sweep B, adjudicated) — OL ≥ QB (QB not the sole steepest), RB out-values WR (inverts NFL), TE is the lowest-value group (but live, not dead).

Nothing is broken or exploit-degenerate; the issues are tuning/calibration. Health is **CONCERNS** with items #1 and #2 sitting at the CRITICAL edge.

---

## Campaign Methodology

- **Harness:** `tools/balance-harness/run.sh` compiles the shipped simulation math with `swiftc -O` outside the iOS app and runs Monte-Carlo scenarios reading the engine's own `BoxScore`. It never touches `dynasty/dynasty/**`.
- **SHA discipline (mandatory, re-verified for this report):** every `run.sh` first runs `sync_sources.sh`, which copies 17 engine sources **verbatim** and asserts `sha(copy)==sha(repo)` for each, **regenerates** the adaptive-AI extract and fails the build if any of 39 tuning lines differ, and splices SimPlayer/GameModels drift-proof. A single mismatch aborts the build. This exists because rounds 2–3 shipped wrong numbers off a hand-copied shim that had silently drifted (`paKeyCompletion` 0.18 vs real 0.035). I recomputed the sync clean at HEAD `4aa54d3` before every re-run below.
- **Sample sizes / RNG:** per-play cells N=40 000; full-game campaigns N=300–1500. `--seedable` fixes **roster** draws (SplitMix64); the engine's play-by-play uses Swift's global **unseeded** RNG, so every game carries Monte-Carlo noise (±~0.1 ypc, ±~0.5pt comp%) — which is why shallow-signal metrics (e.g. TE win%) require large N to read. Throughput ~600 games/sec.
- **Tier bands:** elite 88–95, good 80–87, avg 70–79, weak 55–69. Per-play tiers use band midpoints (weak 62 / avg 74 / good 83 / elite 91).

---

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

---

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

---

## Per-Play EV — Play-Choice Balance (Sweep A)

**No dominant call at any parity.** Max within-family EV ratio (best/worst call) across all 4 equal-talent tiers = **1.38** (inside runs @ weak, dive/draw); every family/tier < 1.4 (edge 1.01–1.03, short 1.19–1.24, mid 1.08–1.09, deep 1.05–1.08). Top-EV call per family is stable across tiers (inside=dive, edge≈flat-tie, short=flat, mid=wheel, deep=flood). Favorable mismatch (ELITEoff/weakDEF) also balanced (max 1.18). All 28 calls rise **monotonically** weak→elite with zero zigzags. Stable on independent re-sample (±0.02).

**Localizes the "passing runs hot" finding to the play level:** equal-tier per-call mid-pass net-YPA is 9.3–11.1 and deep/PA 9.2–10.4 at good/elite, exceeding the full-game net-YPA band (5.9–7.5); even avg=avg mid/deep ~8.7–9.1 > 7.5. The steep offense-favoring monotone rise is present at the raw per-call layer, before any full-game play-selection compounding.

**Extreme-mismatch run-collapse artifact:** at weakOFF/ELITEdef (62/91) the run game collapses to a near-zero floor (best inside dive 2.22 ypc, edge outsideRun 0.56 / jetSweep 0.07 ypc at 77% stuff), blowing the within-family EV ratio to 2.26 (inside) / 7.80 (edge). This is a **small-denominator artifact** of the talent curve being too steep at extremes (corroborates Sweep C's finding #2), **not** a genuinely dominant call — every run option there is bad. Reproduces on independent sample.

---

## Degenerate Strategies Found

No hard-degenerate (strictly-dominant, exploit-breaking) strategy exists — the per-play layer is clean. Three **soft** degenerate leans, all downstream of the two systemic issues:

- **"Just pass more."** Symmetric play-style ladder: run-heavy **29.4** < balanced **32.4** < pass-heavy **35.8** pts/g; run-heavy loses **−9.4pp** win rate vs balanced (Sweep D). The mechanism (opportunity cost of foregoing the hot pass) is healthy, but the pass-favoring tilt is a direct consequence of the systemic passing inflation — the optimal meta is pass-skew, not balance.
- **Familiarity as a near-auto-win lever.** At equal talent, fam100 vs fam33 wins ~93% (re-confirmed 93.2%), 66% of games 3-score blowouts. Rushing your own scheme install or catching an opponent at low familiarity is worth more than a full talent tier — a lever strong enough to distort roster/scheme decisions.
- **Weak-tier pass-skew.** At the weak tier the run game is underpowered (ypc 3.37, rush 91.6) while passing stays hot, so even at low talent the correct call distribution over-indexes on passing.

None is exploit-breaking, but all three reward the same behavior (pass, and maximize familiarity) more than a balanced NFL meta would.

---

## Systems Verdicts (Sweep D — adaptation / familiarity / heat)

- **Adaptation (run-heavy vs balanced): PASS.** Run-heavy correctly **loses** (45.2% vs 54.5% net win, −9.4pp). Mechanism is opportunity cost, not a dramatic rush collapse — run-heavy actually gains rush volume (127 vs 108 yd) at slightly lower efficiency (ypc 3.98 vs 4.03). RunKeyState/PlayMemory per-carry punishment is mild in full games (ypc 4.02→3.96 when keyed) because play-type varies; the net anti-run-heavy outcome is correct and non-degenerate. **Direction right, magnitude healthy.**
- **Familiarity: DIRECTION PASS, MAGNITUDE FAIL (over-punishes).** fam100 beats fam33 **92.7%** net (+28.6 margin) at equal talent — re-confirmed 93.2% / +27.0 — past the 85–90% guardrail, rivaling the uniform elite-vs-weak talent extreme. Carried by passing: the fam33 **defense** surrenders ~500 pass-yds/g and 10.5 net-YPA (coverage-bust term appears **uncapped**), while the fam33 offense's own passing collapses to 52.8% cmp / 6.28 net-YPA. Gradient is **convex** (fam66-vs-33 = 88.0%, re-confirmed 87.6% > fam100-vs-66 = 70.8%), so fam~33 is a **cliff**. A barely-installed scheme should not be a ~93% automatic loss giving up 500+ pass yards.
- **Heat = variance, not free EV: PASS with a minor caveat.** EV-neutral at game grain (sensitive 32.5 vs immune 32.4 mean pts) and higher variance for sensitive rosters (score sd 10.8 vs 10.6; drive-level 10.1 vs 9.4; blowout +1.8pp). **Caveat/flag:** heat carries a **small net-positive EV bias** — macro Δmean +0.34 (N=400) to **+0.83** (N=2000, above the ±0.6 guard); over 12 000 drives Δcmp **+0.97pp** and Δypc **+0.13**, both breaching the harness's own non-inflation tolerance. Cause: asymmetric magnitude (hot +3.8pp cmp / +0.31 ypc exceeds cold −3.0pp / −0.16) plus success-feeds-heat feedback, so a ~0-mean process nets slightly positive. ~85% variance, ~15% EV lean. Streaks are well-formed (+0.34/success, clamp +1.0 after ~3, ×0.80/drive decay) but low-visibility in box scores (damped by ~130-play aggregation).

---

## Progression / Talent-Value Analysis

**Equal-tier scaling is not talent-neutral — it is steeply offense-favoring.** Every one of the 28 per-call EVs rises monotonically weak→elite (insideRun +40%, curl +43%, short comp 57→75%), and full-game points climb 26.5→33.0→36.5→39.8 weak→elite. So mutual talent raises efficiency (especially passing) rather than cancelling out. Combined with the mismatch curve (good-vs-avg 98.6%, elite-vs-weak 100%), the **talent→outcome curve is convex and too steep**: one tier of separation is nearly decisive, two tiers is deterministic. NFL talent gaps compress far more.

**Home-field tilt grows with tier** (minor): 48/52/54/57% home weak→elite (Sweep C). My avg-avg re-run landed 58% home (vs Sweep C's reported 51.6%) — the win-split % carries seed/Monte-Carlo noise (margin means differ <2pt on sd-17), so treat the exact per-tier home% as **low-confidence**; the directional "tilt grows with tier, slight over-tilt at good/elite" holds, the precise numbers do not.

---

## Recommendations

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

---

## Values That Need Attention

- **Full-game pass efficiency (play-selection layer):** net-YPA lands 8.6 at avg vs band 5.9–7.5. Target a ~1.1–1.5 net-YPA reduction at avg (→ ~7.2), which should pull points 33→~27, 3rd-down 53→~45, total-yds 452→~400 into/near band. This is a play-mix / situational-passing weighting knob, **not** a per-play attribute constant (per-play bands themselves pass).
- **Talent→EV slope:** equal-tier points span 26.5→39.8 (weak→elite) and per-call EV rises +24–43%. Compress so equal-tier points span ~24→~30 and mismatch win% caps at ~90%. Elite-vs-weak must not be 100%.
- **Familiarity defensive coverage-bust term:** appears **uncapped** (fam33 D allows ~500 pass-yds / 10.5 net-YPA). Add a hard cap and compress the low-fam curve so fam~33 isn't a ~93%-loss cliff (fam66-vs-33 = 88% is already too steep).
- **Heat magnitude asymmetry:** hot +3.8pp cmp / +0.31 ypc vs cold −3.0pp / −0.16 — symmetrize to eliminate the +0.6–1.0pp net inflation.
- **TE headline response:** cmp +3.8pp / passYds +33 over a 40-grade swing (vs WR +12 / +115). Live and monotone (re-verified), but the flattest of the nine — confirm intended.

---

## Follow-up List (prioritized by size)

**S (small, isolated tuning):**
- Symmetrize heat hot/cold magnitude (P3) — one asymmetric-response constant.
- Cap the familiarity defensive coverage-bust penalty (part of P1) — a single clamp.
- Raise the weak-tier run floor (P3) — folds into the curve work.

**M (medium, one subsystem):**
- Compress the familiarity fam→effect curve at the low end (P1) so fam~33 is not a cliff.
- Rebalance RB-vs-WR win response (P2) and decide OL-vs-QB steepness (P2).
- Verify/adjust TE target share & attribute weighting (P1) — after re-confirming it is not a dead attribute.

**L (large, cross-cutting calibration):**
- **Retune full-game situational play-selection** to remove the systemic passing/scoring inflation (P0) — touches the whole box-score and the pass-skew meta; re-run the full Sweep C band table after.
- **Compress the talent→outcome curve** (P0) so mismatches scale like the NFL (one tier ~70%, two tiers ~85–90%, never deterministic) — touches per-play EV, position sweeps, and every mismatch scenario; re-run Sweeps A/B/C after.

---

## Final League-Health Verdict

**CONCERNS — playable and internally consistent, not shippable-balanced yet.** The foundation is sound: no dominant play call (max within-family EV ratio 1.38), clean monotone position discrimination across all 9 groups, believable asymmetric-unit signatures, and adaptation/heat systems that behave as intended. Independent re-runs at HEAD `4aa54d3` (SHA-verified, no drift) reproduced every headline number to within Monte-Carlo noise, and **overturned one sweep claim** — TE is a live, monotone, lowest-value position, **not** the "dead-attribute" bug Sweep B reported.

The blockers are two **P0 calibration** issues — systemic passing/scoring inflation at every tier, and an over-steep talent curve that makes one-tier gaps near-decisive and two-tier gaps deterministic — plus a **P1** familiarity term that over-punishes to near-determinism. All three are tuning problems in situational play-selection and talent/familiarity response curves, not structural breaks or exploitable degeneracies. Fix the two P0 curves and cap the familiarity bust term and the league moves from **CONCERNS** to **HEALTHY**.
