# NFL Player Development & Training Reference — Calibration Targets (Phase 2)

Companion to `DRAFT_NFL_REFERENCE.md` (whose §6 hit-rates-by-round, §7 rookie
contribution and §8 development-curve norms are the *outcome* targets this file
deepens). Purpose: every constant in the development/training overhaul must
trace to a number or documented pattern here. `~` marks estimates.

## 1. Aging curves per position (growth → peak → decline)

Peak-age findings across EPA/PFF-WAR studies (2014–2024 data):

| Position | Growth years | Peak window | Decline onset | Decline character |
|---|---|---|---|---|
| RB | 21–23 | **24–26** (avg peak 25.5) | **27** | Sharpest cliff in football: share of peak seasons 28→8.7 %, 29→5.2 %, 30→3.8 %. Workload-accelerated. |
| WR | 22–25 (Y2–Y3 leap) | **26–27**, broad 24–30 | 31–32 | EPA stays high to ~31, moderate decline after; possession types last longest |
| TE | 23–26 (slow start) | 26–29 | 31 | Late arrivals common (blocking+route double load) |
| QB | 22–27 (processing growth) | **26–33** | 36+ | Physical arm decay slow; processing keeps improving; elite tail to late 30s |
| OT/IOL | 23–26 | 27–31 | 32–33 | Technique offsets athletic loss; longest careers among non-specialists |
| EDGE | 23–25 | 25–29 | 30–31 | Burst-dependent; power rushers age better than speed rushers |
| DT | 23–25 | 25–29 | 30 | |
| LB | 22–24 | 24–28 | 29–30 | Speed-dependent |
| CB | 22–24 | **24–27** | 29–30 | Rapid early-30s falloff (only 31 of 366 active DBs are 30+); zone/slot age better than press-man |
| S | 22–25 | 25–28 | 30 | Instinct positions decay slower than man-cover |
| K/P | any | 27–37 | 40+ | |

Growth magnitudes (consistent with `DRAFT_NFL_REFERENCE.md` §8): year 1→2
average +8–12 % effectiveness (the biggest single jump), year 2→3 +4–6 %,
year 3→4 +0–3 %, then plateau. Decline: speed positions −2–4 %/yr after onset,
RB/CB steepest; QB/OL/K −1–2 %/yr and later.

## 2. Career trajectory shapes — most players never reach their ceiling

The single most important realism fact: **potential is a ceiling few touch.**
Draft-slot hit rates (`DRAFT_NFL_REFERENCE.md` §6) are the outcome anchor:
R1 ~55–65 % become primary starters, R7 ~14 %, and elite outcomes in R3–7 are
~0.5 %. The spread between identically-projected players comes from:

- **Trajectory mix** (share of drafted players, ~NFL observed):
  - **Ascender** (~25 %): grows years 1–3 toward or near ceiling; starter+.
  - **Plateauer** (~40 %): reaches a level by year 2–3 and *stays there* —
    "he is what he is". Depth/rotational. Most common outcome.
  - **Bust/washout** (~25 %): never establishes; out of the league in 3–4 years
    (R5–7 skew; whole rounds' worth of picks).
  - **Late bloomer** (~10 %): breakout year 3–5 after scheme/coach/opportunity
    change — OL, TE, QB overrepresented (e.g. career backups turned starters).
- Breakout timing: >50 % of first-time WR1 seasons come in year 2–3; year-2 QB
  leap is the classic pattern; rookies contribute at 55–85 % of eventual level.
- If a player is not starter-quality by the end of the rookie deal (year 4),
  odds of ever becoming one drop to ~10 %.

**Differentiators that decide the trajectory** (all should be modeled, roughly
in order of impact): opportunity/snaps · work ethic · learning speed/football
IQ · competitiveness (response to adversity) · coaching quality & continuity ·
health · scheme fit · off-field stability.

## 3. Contract-year and payday effects (evidence-based, modest)

- **Contract-year bump**: studies range from "myth" to **~+5 % average**;
  strongest for skill positions playing for a first big deal. Model as a small,
  visible motivation bump — not a superpower.
- **Post-guarantee dip**: the robust finding. Performance surrounding the
  contract year averages **materially lower when >⅓ of the deal is guaranteed**
  (one WPA study: −36.9 % swing vs low-guarantee deals); QB studies 1985–2022
  find a negative post-signing season effect. Model: a *complacency roll* the
  season after a big extension, gated by competitiveness/work ethic (high-drive
  players are immune — Brady/Rice archetypes; low-drive players regress).
- Extension-year dip is temporary (~1 season) absent age decline.

## 4. Motivation & adversity (the "fighter mentality" layer)

Documented, recurring NFL patterns to model as a motivation state machine:

| Trigger | Typical response | Gate |
|---|---|---|
| Team collapsed last season (big miss vs expectations) | Offseason "best shape of my life" push for competitors; checked-out veterans on rebuilders | competitiveness high → **driven**; low + old → coast |
| Personal down year / demotion / benched | Prove-it response or confidence spiral | competitiveness + morale |
| Draft slide / doubted (rookie chip) | Multi-year motivation (Brady p199, Rodgers-style chips) | competitiveness |
| Contract year | +small bump (§3) | — |
| Just paid (high guarantee) | Complacency risk (§3) | competitiveness/work ethic |
| Playoff heartbreak (close loss deep in playoffs) | Team-wide offseason edge | leadership/culture |
| New scheme/coordinator | Learning tax year 1 (install), gain year 2 | learning + coach expertise |

Motivation should move **training output** (development points, weekly gain
chance) and slightly morale — not directly game ratings.

## 5. Coaching impact & continuity

- Hierarchy of direct development influence (matches the game's existing
  0.5–1.8× stack): position coach > coordinator > strength staff > HC culture.
  Documented "QB guru"/"OL whisperer" effects: a top position coach visibly
  accelerates young players at his position group year over year.
- **Continuity matters as much as quality**: an OC/scheme change costs a
  measurable install year (offenses under a new OC underperform year 1,
  recover year 2); young QBs churned through coordinators develop worse —
  stability should compound development, changes should tax it (the game's
  `isInAdjustmentPeriod` and scheme-familiarity systems already model pieces).
- Strength/conditioning staff: injury-rate and durability effects more than
  skill effects.
- Coach *development reputation* is a real free-agency/draft lure (out of
  scope now, note for later).

## 6. Practice structure & where development actually happens

CBA reality — the calibration for *when* growth occurs:
- Offseason program + OTAs (~10 voluntary sessions) + mandatory minicamp +
  **training camp = the growth window**. In-season: max 14 padded practices,
  wednesday–friday walkthrough rhythm → in-season skill growth is small;
  game reps are the main in-season teacher (the game's offseason-heavy
  `developPlayer` + small weekly ticks match this shape — keep it).
- Young players live on scout-team/backup reps: real but reduced development
  without game snaps (model a practice-reps floor, not zero).
- QB2 "clipboard" development is real but slow, and accelerates with a good QB
  room (position coach + veteran mentor).
- Rookies who miss camp (holdout/injury) start the season visibly behind —
  a missed camp should cost a chunk of the year's growth.

## 7. Injury effects on development

- Major injury (ACL-class, ≥ half season): year-of-return performance ~85–90 %
  of baseline, full recovery year 2 — model as a temporary effectiveness dip +
  lost development cycle, not permanent attribute loss (permanent loss only for
  repeat/major cases — the game's 15 % durability hit on heal is fine).
- A season-ending injury costs that year's growth window (skip offseason gains
  if rehabbing through it), and pushes the age curve right by ~half a year for
  skill positions.
- Recurring soft-tissue pattern: low durability should compound (existing
  WorkloadEngine direction is right).

## 8. League-level equilibrium targets (the ratchet fix's success criteria)

A realistic league in steady state (multi-season harness gates):

- **League average OVR stable**: drift ≤ ~0.3–0.4/season after a 2–3 season
  transient; no monotone ratchet over 5–10 seasons.
- **Age pyramid**: roster median age ~25.5–26.5; ≤ ~2 % of players 33+;
  rookie-contract players (yp 0–3) ≈ 45–55 % of the league.
- **Quality pyramid** (share of ~1 700 rostered players): 90+ OVR ~1–2 %
  ("blue chip" ~25–35 players league-wide), 80+ ~12–16 %, starter-quality 75+
  ~30–40 %, sub-65 depth/ST ~25 %.
- **Turnover**: ~250–300 new players/year in (224 picks + UDFAs), matching
  retirements+washouts out; average career ~3.3 yrs, drafted-player average
  ~5 yrs, R1 average ~9 yrs.
- **Outcome rates by round reproduce `DRAFT_NFL_REFERENCE.md` §6** when
  careers are simulated end-to-end through the development engine — this is
  the definitive test that potential + realization + regression are jointly
  calibrated (not any single knob).

## 9. Modeling directives distilled (for the design doc)

1. Realization gap is the core mechanic: same potential, four trajectory
   archetypes (§2 shares) emerging from work ethic × competitiveness ×
   learning × opportunity × coaching × health — never a direct "trajectory
   roll" visible to the player.
2. Motivation is a *state*, recomputed each offseason (+ small in-season
   events), that multiplies training output (§4 table).
3. Contract effects small and gated (§3): +bump in contract year, complacency
   roll after big guarantees.
4. Coaching: quality × **continuity**; changes tax a year, stability
   compounds (§5).
5. Growth lives in the offseason window; in-season = game-experience +
   small focus ticks (§6). Missed camp = lost growth.
6. Regression is position-shaped (§1): RB/CB cliff, QB/OL glide.
7. Potential can drift a few points (realization events, scheme fit, morale)
   but outcomes are decided by realization, not potential inflation.
8. All of it must jointly reproduce §8 league equilibrium + §6 draft-slot hit
   rates in simulation — calibrate the system, not the knobs.

## 10. Sources

- [PFF — aging curves by position](https://www.pff.com/news/fantasy-football-metrics-that-matter-aging-curves-by-position); [PFF — positional aging with WAR](https://www.pff.com/news/nfl-investigating-positional-aging-curves-with-pff-war); [Dynasty Edge — EPA age curves 2014–2024](https://thedynastyedge.com/2025/06/21/nfl-age-curve-study-epa-trends-by-position-rb-wr-te-qb-fantasy-football-analysis-2014-2024/); [Apex — RB peak age](https://apexfantasyleagues.com/peak-age-nfl-running-back/); [ESPN — peak/decline ages](https://www.espn.com/fantasy/football/story/_/id/37933720/2023-fantasy-football-players-peak-decline-quarterback-running-back-wide-receiver)
- [Wikipedia — contract year phenomenon](https://en.wikipedia.org/wiki/Contract_year_phenomenon); [ScienceDirect — do players perform for pay](https://www.sciencedirect.com/science/article/abs/pii/S0378426618300098); [SSRN — contract incentives & performance](https://papers.ssrn.com/sol3/Delivery.cfm/5492367.pdf?abstractid=5492367&mirid=1); [ScienceDaily — timing of NFL contracts](https://www.sciencedaily.com/releases/2014/07/140723123851.htm)
- [FantasyLife — Y2–3 WR breakouts](https://www.fantasylife.com/articles/fantasy/year-2-3-wide-receiver-breakouts-for-fantasy-football); [FantasyPros — breakout WR analysis](https://www.fantasypros.com/2025/06/identifying-the-next-breakout-wide-receivers-fantasy-football/); [NFL.com — year-2 WR breakouts](https://www.nfl.com/news/five-nfl-wide-receivers-poised-to-break-out-in-year-2)
- Hit rates / rookie contribution / dev-curve norms: `docs/DRAFT_NFL_REFERENCE.md` §6–§8 and its sources.
