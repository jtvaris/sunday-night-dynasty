# QA_REPORT v2 — `tools/league-data/raw/` (2026 raw league snapshot)

Independent re-validation of the schema-v2 rebuild. Nothing in the builder or in
`_build_summary.json` was taken on trust: every gate, count and coverage figure below was
re-derived from the artifacts on disk, and the stat pipeline was reconciled field-by-field
against the source CSV.

**Verdict: GO.** 0 hard errors, 0 gate violations, 0 schema errors across 32 teams /
1807 players / 7526 season rows. All 15 items on the v1 P0–P3 list are done or accounted
for. Every v1 BLOCKER (B1–B4) and every v1 MAJOR (M1–M5) is resolved or explicitly bounded.
One residual defect class remains — the depth chart is a one-season volume ranking (§4) —
and it is a data-quality caveat for the importer, not an integration blocker.

Merged output: `league_raw_2026.json` (3.81 MB), re-merged with the audit result embedded
in `qa.independentAudit` and `qa.depthOrderSuspects`.

---

## 1. How this was verified

| Check | Method |
|---|---|
| Schema | Key set, type and range asserted on every team, player, season row and `post` sub-object. Stat keys asserted against the documented per-position shape. |
| Gates | All 12 gates recomputed from scratch — roster band, QB/OL/K/P/DB counts, 11 offensive + 11 defensive + 2 ST starters, per-position starter quota, `depthChartRank` permutation, `gs <= gp`. |
| Staffs | Decoded through a **real Swift `JSONDecoder`** into `OffensiveScheme` / `DefensiveScheme` from `dynasty/Domain/Enums/Scheme.swift`. Not a string comparison. |
| Stats | 1231 individual 2025 stat fields (QB att/comp/yds/td/int, skill rec/recYds) compared to `_sources/stats/player_stats_reg_2025.csv`. |
| Draft | Pick contiguity, per-round standard-pick uniqueness for all 32 original teams, round-1 order vs `draftOrder2026`, `record2025` cross-file agreement. |
| Merge | Every team object, the draft doc and the staffs doc byte-compared against their standalone files after re-merging. |

**Stat cross-check result: 1231 fields compared, 0 mismatches.** 14 skill players carry an
all-zero 2025 row with no nflverse REG row — they appeared in a game without recording a
stat. Zeros, not fabrication.

---

## 2. Completeness table v2

| Data class | v1 | **v2** | Basis |
|---|---:|---:|---|
| Roster / structure (32 teams, schema-valid, all gates) | 100.0% | **100.0%** | 32/32 files, 1807 players, 0 schema errors, 0 gate violations |
| Bio — age / heightIn / weightLb / yearsPro | 100.0% | **100.0%** | 0 nulls, all in range |
| Bio — **jersey number** | 0% | **100.0%** | 0 nulls / 1807, keyed by (player, team) |
| Bio — college | 99.72% | **99.72%** | 5 nulls / 1807 (unchanged; needs a non-nflverse source) |
| Draft origin (non-null `draft{}`) | 74.05% | **74.05%** | 469 UDFA = 25.95%, matches real roster composition; all adjudicated in v1 |
| **League structure — conference / division** | 0% | **100.0%** | on every team file + `league_raw_2026.json.divisions`; 8 divisions × 4 |
| Career — player has ≥1 season row | 99.00% | **99.06%** | 17 players / 1807 with `seasons: []` |
| **Career — season-year coverage** | 67.9% | **95.23%** | 7526 / 7903 expected rows (window widened to 2010–2025) |
| Career — season row has non-empty `stats{}` | 83.3% | **100.0%** | 0 empty rows league-wide (was 895, all OL) |
| Career — `gp` non-null | 88.71% | **99.91%** | 7 null rows |
| **Career — `gs` non-null** | 0.0% | **95.75%** | 7206 / 7526; provenance per row in `gsSrc` |
| **OL rows with both `gp` and `gs`** | 0% | **97.82%** | 1255 / 1283 OL rows |
| `snapShare` populated | n/a | **93.66%** | 477 null (pre-2013, or no PFR snap row) |
| Postseason split out of the REG row | 0% | **100.0%** | 2279 `seasons[].post` sub-objects; REG rows are REG-only |
| Coaching staffs — name slots | 98.96% | **98.96%** | 95/96; only TB DC null (Bowles calls it himself) |
| **Coaching staffs — scheme decodes in Swift** | 0% | **100.0%** | **32/32** via real `JSONDecoder` |
| 2026 picks | 100.0% | **100.0%** | 257/257, contiguous 1–257, 1 standard pick per round per original team |
| Draft order | 100.0% | **100.0%** | 32 unique, exact match to round-1 `originalTeam` order |

### `gs` provenance (7206 rows)

| Source | Rows | What it is |
|---|---:|---|
| `pfrAdvStats` | 3958 | PFR advanced season tables 2018–2025 (skill + defense) |
| `pfrRoster` | 2215 | PFR team roster table GS 2010–2022 (authoritative, all positions) |
| `snapStart50` | 843 | **derived proxy**, OL only: games at ≥50% of team offensive snaps |
| `pfrConventionKP` | 190 | 0 for a K/P who played — PFR's convention on all 1827 K/P team-seasons on disk |

320 rows remain null, concentrated in 2022–2025 (127 in 2025) where the PFR roster tables
stop and a player is absent from the advanced tables. Spread thinly across every position;
no position is systematically dark.

---

## 3. Per-team table v2

`o`/`d`/`s` = offensive / defensive / special-teams starters. `cov%` = career season-year
coverage. `gs%`/`gp%` = season rows with `gs`/`gp`. `OLgp%` = OL rows with both.
`ud` = undrafted. `c0` = null colleges. `ns` = players with no season rows.

```
tm  cf  div      n  st  o  d  s rot bkp dep IR   QB RB FB WR TE OL DE DT OLB MLB DB K P  base  rows  exp  cov%   gs%   gp%  OLgp%  ud c0 ns
ARI NFC West    57  24 11 11  2  19  13   1   3   2  3  0  6  5 10  4  5   6   2 11 2 1  4-3    205  218  94.0  95.6 100.0   97.1  14  0  1
ATL NFC South   56  24 11 11  2  19  10   3   3   3  3  0  7  4  9  5  2   4   5 11 1 2  3-4    244  268  91.0  94.3 100.0   95.0  15  0  0
BAL AFC North   57  24 11 11  2  18  13   2   3   3  4  1  7  3  9  5  1   5   6 11 1 1  3-4    245  253  96.8  97.6 100.0  100.0  13  1  0
BUF AFC East    57  24 11 11  2  26   5   2   3   2  4  1  7  4  9  4  6   5   1 12 1 1  4-3    281  288  97.6  98.2  98.9   94.7  10  0  0
CAR NFC South   55  24 11 11  2  18  12   1   3   2  3  0  6  4 10  5  2   5   6 10 1 1  3-4    223  230  97.0  94.6 100.0   98.1  16  0  1
CHI NFC North   56  24 11 11  2  16  15   1   3   3  3  0  6  4 10  4  4   6   2 12 1 1  4-3    259  266  97.4  95.4 100.0   97.4  15  0  0
CIN AFC North   57  24 11 11  2  18  15   0   3   3  3  0  6  5  8  7  6   3   2 12 1 1  4-3    232  244  95.1  97.4 100.0  100.0  13  0  0
CLE AFC North   56  24 11 11  2  26   5   1   3   2  3  0  6  5 12  4  5   3   3 11 1 1  4-3    209  224  93.3  95.2 100.0   98.2  21  0  1
DAL NFC East    55  24 11 11  2  24   7   0   3   2  3  1  6  3  9  5  6   3   3 12 1 1  4-3    214  225  95.1  95.3 100.0   86.7  13  0  0
DEN AFC West    57  24 11 11  2  19  13   1   3   3  4  1  7  3  9  5  2   5   5 11 1 1  3-4    237  260  91.2  95.8 100.0  100.0  18  0  0
DET NFC North   56  24 11 11  2  19  13   0   3   2  4  0  6  5 10  5  5   5   1 11 1 1  4-3    267  279  95.7  95.9 100.0  100.0  20  0  0
GB  NFC North   56  24 11 11  2  26   4   2   3   3  3  0  7  3 10  8  5   4   1 10 1 1  4-3    185  193  95.9  94.1  99.5   88.6  12  0  0
HOU AFC South   56  24 11 11  2  27   4   1   3   3  5  0  7  3  9  5  6   4   2 10 1 1  4-3    259  264  98.1  97.7 100.0  100.0  10  0  1
IND AFC South   56  24 11 11  2  19  12   1   3   4  4  0  5  4  9  5  6   5   1 11 1 1  4-3    253  264  95.8  94.9 100.0  100.0  14  0  1
JAX AFC South   55  24 11 11  2  22   9   0   2   2  4  0  7  4  9  6  5   4   2 10 1 1  4-3    254  262  96.9  98.4 100.0  100.0  13  0  0
KC  AFC West    57  24 11 11  2  16  15   2   3   3  4  0  6  4 10  5  5   5   2 11 1 1  4-3    228  245  93.1  93.9 100.0  100.0  14  1  1
LA  NFC West    56  24 11 11  2  21  10   1   2   3  4  0  6  5 10  5  2   4   4 11 1 1  3-4    224  232  96.6  97.3 100.0  100.0  14  0  1
LAC AFC West    57  24 11 11  2  25   7   1   3   2  5  1  7  4 10  3  2   5   5 11 1 1  3-4    246  255  96.5  97.2 100.0   98.1  10  0  1
LV  AFC West    57  24 11 11  2  20  13   0   3   3  4  0  6  3 10  6  5   4   3 11 1 1  4-3    223  236  94.5  94.2 100.0   96.7  16  0  0
MIA AFC East    57  24 11 11  2  22   9   2   3   4  5  1  7  3  9  3  6   4   3 10 1 1  4-3    233  248  94.0  96.6 100.0  100.0  18  0  2
MIN NFC North   57  24 11 11  2  17  15   1   3   4  4  1  6  4 10  4  2   6   4 10 1 1  3-4    229  247  92.7  94.8 100.0   91.7  23  0  0
NE  AFC East    57  24 11 11  2  20  11   2   3   3  3  2  6  3 10  5  2   5   6 10 1 1  3-4    214  221  96.8  96.3  99.5  100.0  17  0  1
NO  NFC South   57  24 11 11  2  21  11   1   3   3  4  0  7  4 10  5  2   5   5 10 1 1  3-4    219  236  92.8  95.4 100.0   96.9  12  1  0
NYG NFC East    57  24 11 11  2  19  13   1   3   3  4  0  8  4  9  4  1   5   5 12 1 1  3-4    237  246  96.3  92.4 100.0   98.0  24  0  0
NYJ AFC East    57  24 11 11  2  21   8   4   3   4  4  1  6  4  9  6  5   3   2 11 1 1  4-3    195  211  92.4  95.4 100.0   96.6  17  1  2
PHI NFC East    57  24 11 11  2  22  10   1   3   3  4  1  5  4 10  4  1   6   5 12 1 1  3-4    229  240  95.4  96.5  99.6   97.9   7  1  0
PIT AFC North   57  24 11 11  2  21  10   2   3   3  3  1  7  3 10  4  2   5   5 12 1 1  3-4    259  277  93.5  97.7 100.0  100.0  10  0  1
SEA NFC West    56  24 11 11  2  14  18   0   2   3  5  2  6  4  9  6  5   3   3  8 1 1  4-3    211  212  99.5  91.9 100.0  100.0  14  0  0
SF  NFC West    57  24 11 11  2  23   8   2   3   2  4  1  6  4  9  7  6   4   2 10 1 1  4-3    245  260  94.2  96.3 100.0  100.0  11  0  1
TB  NFC South   56  24 11 11  2  20  11   1   3   3  3  0  7  3 11  4  2   6   4 11 1 1  3-4    248  253  98.0  96.4  99.6   97.8  11  0  1
TEN AFC South   56  24 11 11  2  21  11   0   3   2  4  0  6  4 11  4  2   5   5 11 1 1  3-4    212  229  92.6  93.9 100.0   97.6  17  0  0
WAS NFC East    57  24 11 11  2  20  10   3   3   5  4  0  5  4 11  3  6   6   2  9 1 1  4-3    307  317  96.8  95.4 100.0   98.3  17  0  1
```

Every team: 55–57 players, 24 starters, **11 offensive + 11 defensive + 2 ST**, 1 K, 1 P,
conference and division present, `baseDefense` present.

---

## 4. Spot-checks demanded by the wave

### 4.1 The 7 flagged QB rooms — **5 fixed, 2 still wrong**

| Team | v1 starter | **v2 starter** | Correct? | 2025 att / snapShare |
|---|---|---|:-:|---|
| KC | Chris Oladokun (55 att) | **Patrick Mahomes** | ✅ | 502, .974 — IR at season end, still ranks 1 |
| DEN | Jarrett Stidham (31) | **Bo Nix** | ✅ | 612, .996 |
| IND | Philip Rivers (92, age 44) | **Daniel Jones** | ✅ | 384, .915 |
| MIA | Quinn Ewers (83) | **Tua Tagovailoa** | ✅ | 384, .954 |
| ATL | Kirk Cousins (269) | **Michael Penix Jr.** | ✅ | 276, .932 |
| NYJ | Brady Cook (153) | **Justin Fields** | ✅ | 204, .898 |
| **CIN** | Joe Burrow | **Joe Flacco** (age 41) | ❌ | Flacco 416 att @ .778 vs Burrow 259 @ .878 |
| **WAS** *(not v1-flagged)* | — | **Marcus Mariota** (age 32) | ❌ | Mariota 227 @ .745 vs Daniels 188 @ .903 |

The v1 blocker is genuinely fixed: `role: ir` is gone, and a franchise QB who finished the
year on IR now outranks his replacement (KC, DEN, IND, NYJ, ATL all flipped correctly).
CIN and WAS fail for a different reason — **the rule ranks on total volume, and both
franchise QBs were out-*volumed* while leading on rate, and neither was on IR at season
end**, so `injuredAtSeasonEnd` does not catch them. See §4.3.

### 4.2 The 4 broken lineups — **all 4 fixed**

| Team | v1 defect | v2 |
|---|---|---|
| CAR | 6 OL starters, two centers (Corbett + Mays) | 11 off / 11 def. OL = Ekwonu / Lewis / **Mays (C, alone)** / Christensen / Moton; Corbett is C2 |
| LAC | two LT starters, no RT starter | 11 off / 11 def. LT = Deculus, RT = Pipkins, one each |
| KC | 9 defensive starters | 11 def: CB2 Nohl Williams and OLB Cooper McDonald added |
| NO | 9 offensive starters (1 WR) | 11 off: 3 WR (Olave / Vele / Tipton) |

Enforced structurally on all 32 teams by the quota gate, which I recomputed independently —
no team exceeds or misses any positional starter quota.

### 4.3 Residual: the depth chart is a one-season volume ranking

`role` / `depthChartRank` order players inside (team, position) by **total 2025 regular-season
snaps**. A durable fill-in therefore outranks a franchise starter who missed half the year.

**27 of 768 starter slots (3.5%, across 21 teams)** have a benched player who beat the listed
starter on 2025 per-game snap share with a credible sample (≥5 starts, or ≥8 games at ≥55%
share). Full list in `league_raw_2026.json.qa.depthOrderSuspects`. The most conspicuous:

| Team | Pos | Benched (share) | Listed starter (share) |
|---|---|---|---|
| SEA | CB | Devon Witherspoon (.932, 12 GS) | Josh Jobe (.769) |
| IND | CB | Sauce Gardner (.795, 10 GS) | Mekhi Blackmon (.689) |
| IND | DT | DeForest Buckner (.705, 10 GS) | Adetomiwa Adebawore (.460) |
| TB | WR | Mike Evans (.656) **and** Chris Godwin Jr. (.709) | Tez Johnson (.471) |
| LAC | OLB | Khalil Mack (.601, 11 GS) | Odafe Oweh (.479) |
| NO | C | Erik McCoy (.964, 7 GS) | Luke Fortner (.687) |
| MIN | RB | Aaron Jones (.551, 12 GS) | Jordan Mason (.428) |
| CIN | QB | Joe Burrow (.878) | Joe Flacco (.778) |
| WAS | QB | Jayden Daniels (.903) | Marcus Mariota (.745) |

A further 12 candidates were examined and **rejected as small-sample artifacts** (e.g. GB
Lecitus Smith, one game at 100% share) — `snapShare` is a mean over games appeared in, so a
single mop-up appearance produces a meaningless 1.000.

**There is no free fix.** I tested the obvious alternatives:

| Rule | Result |
|---|---|
| Total snaps (current) | 27 suspect slots; QB rooms 30/32 right |
| Attempts per game (QB) | Fixes CIN + WAS, **breaks IND and NYJ** |
| Snap share, min 4 games | Fixes CIN + WAS + 20 suspects, but **moves 67 slots** and breaks correct ones (drops Derek Stingley Jr., Kenneth Walker III, Dallas Turner, Jihaad Campbell) |

A one-season signal cannot distinguish "lost his job" from "was hurt". The honest resolutions
are a small explicit override list, or — better — let the Swift side treat `role` as a hint
and re-derive the depth chart from generated ratings, which it has to do for later seasons
anyway. Also note `LAC LT` was decided by a **6-snap margin** (Deculus 516 vs Hart 510): these
orderings are not robust, and nothing downstream should treat them as ground truth.

### 4.4 Staffs decode 32/32 — verified in Swift, not by string match

A real `JSONDecoder` decoding `coaching_staffs_2026.json` into
`[String: Staff]` with `offScheme: OffensiveScheme` / `defScheme: DefensiveScheme`:

```
DECODED staffs: 32
off: Shanahan 14, ProPassing 6, Spread 5, WestCoast 4, RPO 2, PowerRun 1
def: Hybrid 8, Multiple 7, Base43 6, Cover3 5, PressMan 5, Base34 1
missing DC: ["TB"]
```

Keys are the 32 canonical abbrs (`LA`, not `LAR`) — B1 fixed at source. Every `sinceYear`
is in 1990–2026. 95/96 name slots filled.

**B3 is only partially resolved.** `WideZone` 15/32 became `Shanahan` 14/32 — 44% of the
league still runs one offense, and `AirRaid` and `Option` are produced **zero** times. The
mapping is faithful to the source notes; the collapse is in the underlying scouting prose,
not in the mapping. It is a realism concern, not a correctness one.

### 4.5 `int` / `defInt` split — verified

| | v1 | **v2** |
|---|---:|---:|
| League `int` sum 2025 (blended nonsense) | 785 | — |
| **Interceptions thrown** (QB rows, key `int`) | — | **368** |
| **Interceptions caught** (non-QB rows, key `defInt`) | — | **365** |
| nflverse REG 2025 league-wide thrown (all players incl. non-rostered) | — | 380 |

368 thrown for the rostered subset against 380 league-wide = 96.8% capture — exactly what a
"players still on a 2026 roster" subset should look like, and comfortably inside the
requested 350–500 band. **0 non-QB rows carry a legacy `int` key** and **0 QB rows carry
`defInt`**; the polysemy is fully gone. Same for `td` → `defTd`.

Other 2025 league totals recomputed and plausible: 119,961 pass yds vs 116,184 rec yds
(96.9%); 10,972 completions vs 10,589 receptions (96.5%); 853/995 FG = 85.7%; 1224.5 sacks;
32,780 tackles; 1,874 punts.

### 4.6 Draft file

257 picks, `overallPick` contiguous 1–257 with no duplicates; exactly one standard pick per
round for all 32 original teams (224) + 32 compensatory + 1 resolution pick; `draftOrder2026`
is 32 unique canonical abbrs and matches the round-1 `originalTeam` order exactly;
`records2025` agrees with all 32 team files; every record sums to 17.

---

## 5. Remaining holes

| # | Pri | Hole | Size | Why it is still open |
|---|---|---|---|---|
| 1 | **P1** | **Depth-chart order is a one-season volume ranking** — 27/768 starter slots suspect, incl. CIN and WAS at QB | 3.5% of starters, 21 teams | No single-season rule fixes it without breaking others (§4.3). Needs an override list or ratings-based re-derivation on the Swift side. |
| 2 | P2 | `gs` null | 320 / 7526 rows (4.25%) | PFR roster tables end at 2022; the affected players are absent from the advanced tables too. |
| 3 | P2 | Career coverage | 377 rows short of 7903 (4.77%) | Players whose careers predate 2010, or seasons with no stat/snap/roster row anywhere. |
| 4 | P2 | `snapShare` null | 477 rows (6.34%) | No PFR snap release before 2013; plus players with no `pfr_id`. |
| 5 | P2 | OL `gp`+`gs` | 28 / 1283 OL rows (2.18%) | Worst team DAL 86.7%, GB 88.6%, MIN 91.7%. 843 OL rows use the `snapStart50` **proxy** — near-exact but labelled, and any starts-based OL model inherits that assumption. |
| 6 | P3 | 5 null colleges | Mailata, Stiggers, Smyth, Okoye, Godrick | Not in nflverse. Three genuinely have no US college (rugby / CFL / GAA) and want an explicit sentinel, not `null`. |
| 7 | P3 | 17 players with `seasons: []` | 0.94% | No stat row, no snap, no PFR roster row in 2010–2025 anywhere. |
| 8 | P3 | 2 jersey collisions | BUF #23, IND #17 | Real re-issues after an IR placement. Importer must pick one. `_build_summary.json.jerseyCollisions`. |
| 9 | P3 | Scheme diversity | Shanahan 14/32 (44%); AirRaid and Option never produced | Faithful to the source notes; a realism concern for team identity. |
| 10 | P3 | Thin DL on LAC / NYG / PHI | 5 DE+DT each | Unchanged by design; all three are base 3-4 so 5 is survivable, below the 6 a rotation wants. |
| 11 | m | `_build_summary.json.olRowsWithGamesPct` = 99.77% is an **OR** (`gp` or `gs`) | +1.95 pts optimistic | Fixed in `build_raw.py`: it now also emits `olRowsWithGpAndGsPct` (the AND, 97.82%). The stale 99.77% figure remains in the current `_build_summary.json` until the next full build. |

Nothing here fabricates data. Every unknown is `null` and every derived value is labelled
(`gsSrc`, `snapStart50`, `schemeMapping`, `depthOrderSuspects`).

---

## 6. GO / NO-GO for Swift integration

### **GO** — start the anonymization + `LeagueGenerator` data path.

**What is ready and unblocked:**

- All four v1 blockers are gone. Staffs join on `LA` and decode 32/32 through the real
  Swift enums. Conference and division are on every team file and the 8×4 structure is
  complete — a schedule, standings and playoff seeding can be built.
- Structure is watertight: 32 teams, 55–57 players, 11+11+2 starters, positional quotas
  satisfied, `depthChartRank` a clean 1..n permutation per (team, position).
- Player attributes — the actual `LeagueGenerator` inputs — are essentially complete:
  100% jersey, 100% age/height/weight/yearsPro, 99.7% college, 74% draft origin with the
  remaining 26% adjudicated as genuine UDFAs.
- Career signal is now usable: 95.2% year coverage, 95.8% `gs`, 99.9% `gp`, REG and POST
  separated, OL rows carry snaps instead of nothing. A development / retirement / OVR-arc
  model has something to fit.
- Stat semantics are unambiguous and provenance-verified: 1231 fields matched the source
  CSV exactly, and the `int`/`defInt` split lands at 368 thrown / 365 caught.

**Conditions to carry into the Swift work (none block starting):**

1. **Treat `role` as a hint, not ground truth.** 3.5% of starter slots are demonstrably
   wrong and the orderings are decided by margins as thin as 6 snaps. Re-derive the depth
   chart from generated ratings; use `depthChartRank` + `injuredAtSeasonEnd` + `snapShare`
   as generation inputs, not as the shipped lineup. If a hand-fix is wanted first, CIN QB
   and WAS QB are two edits.
2. **Handle the 2 jersey collisions** explicitly at import.
3. **Decide the `college: null` sentinel** before anonymization runs over it.
4. **Do not treat OL `gs` as measured** — 843 rows are the `snapStart50` proxy. Read `gsSrc`.
5. **Anonymization is mandatory.** This tree is real-name data; per
   `docs/ANONYMIZATION_SPEC.md` §6.5 it lives only in `tools/league-data/raw/` and must
   never enter a shipping target's resources.

---

## 7. Merged artifact

`league_raw_2026.json` — 3.81 MB, re-merged and re-verified.

```
{ schemaVersion: 2, generated, compiledNote, compiledBy, teamAbbrConvention,
  schemaNotes, divisions{8},
  teams:  [32 team objects, verbatim, canonical abbr order],
  draft:  <draft_picks_2026.json verbatim>,
  staffs: <coaching_staffs_2026.json verbatim>,
  qa: { ...build counters,
        independentAudit:    <this report's machine-readable result>,
        depthOrderSuspects:  [27 entries] } }
```

Post-merge assertions, all passing: 32 teams in canonical order; every team object, the
draft doc and the staffs doc byte-identical to their standalone files; 27 depth suspects;
divisions sum to 32. The merge adds **no** content of its own beyond the `qa` block.

`build_raw.py` now carries `QA_V2_AUDIT` / `QA_V2_DEPTH_SUSPECTS`, so a rebuild reproduces
this `qa` block rather than dropping it.

> Real-name data. Never ship without anonymization (`docs/ANONYMIZATION_SPEC.md` §6.5).
