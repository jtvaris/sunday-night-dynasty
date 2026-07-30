#!/usr/bin/env python3
"""
build_raw.py v2 -- deterministically build the 32 per-team raw JSON files for the
Dynasty realistic-starting-league import, by joining the LOCAL nflverse sources in
tools/league-data/raw/_sources/.

No network access at build time. No fabrication: anything that cannot be joined is
emitted as null and counted in the summary. Every derived-by-proxy value carries a
provenance tag (see `gsSrc`).

v2 implements the QA_REPORT.md P0/P1/cheap-P2 list:
  P0-1  coaching_staffs_2026.json re-keyed LAR -> LA
  P0-2  scheme vocabulary mapped onto Domain/Enums/Scheme.swift raw values
  P0-3  conference + division on every team file
  P1-4  seasons[].gs populated from PFR (roster tables + advanced season tables)
  P1-5  role = depth order ENTERING 2026 (season-long primacy), + depthChartRank,
        + injuredAtSeasonEnd (the old `ir` role is gone)
  P1-6  the four broken starting lineups (CAR/LAC/KC/NO) fixed by construction
  P1-7  int/td disambiguated -> defInt/defTd on defensive rows
  P2-8  career window widened to 2010-2025, up to 8 seasons for every player
  P2-9  OL season rows carry gp/gs/snapShare/snaps/penalties (no more empty careers)
  P2-10 season rows are REGULAR SEASON only; postseason moved to `post`
  P2-11 jersey numbers from roster_2025.csv

Inputs (all local, all under raw/_sources/):
  roster_weekly_2025.csv        end-of-season roster anchor (per-team max week w/ ACT)
  roster_2025.csv               jersey numbers
  players.csv                   master bio table (birth date, college, ht/wt, pfr id)
  depth_charts_2025.csv         ESPN depth charts, daily snapshots -> game positions
  snaps/snap_counts_<Y>.csv     PFR snap counts 2013-2025 -> gp / snapShare / OL signal
  gs/pfr_rosters.csv            PFR team roster tables 2002-2022 -> games + games started
  gs/advstats_season_{def,rush,rec}.csv  PFR advanced season tables 2018-2025 -> games started
  draft_picks.csv               1980-2026 draft -> draft origin (season <= 2025 only)
  stats/player_stats_reg_<Y>.csv     nflverse stats_player_reg      2010-2025 (REG)
  stats/player_stats_<Y>.csv         nflverse stats_player_regpost  2010-2025 (REG+POST)
  ../draft_picks_2026.json      records2025 (Wikipedia 2025 NFL season) + SB result
  ../coaching_staffs_2026.json  hand-compiled staffs (normalised in place by this script)

Output (all under raw/):
  <ABBR>.json x32, coaching_staffs_2026.json (normalised), league_raw_2026.json,
  _build_summary.json

Usage:  python3 tools/league-data/build_raw.py
"""

from __future__ import annotations

import csv
import json
import os
import sys
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, timezone

csv.field_size_limit(10_000_000)

# --------------------------------------------------------------------------
# Paths
# --------------------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw")
SRC = os.path.join(RAW, "_sources")
STATS_DIR = os.path.join(SRC, "stats")
SNAPS_DIR = os.path.join(SRC, "snaps")
GS_DIR = os.path.join(SRC, "gs")

# Career window. Season rows are emitted for the most recent MAX_CAREER_SEASONS
# seasons in which the player actually appeared, anywhere inside this window.
CAREER_YEARS = list(range(2010, 2026))
MAX_CAREER_SEASONS = 8
SNAP_YEARS = list(range(2013, 2026))       # snap_counts releases we hold locally
ADVSTAT_YEARS = list(range(2018, 2026))
PFR_ROSTER_MAX_YEAR = 2022

# Age reference date (February 2026 offseason snapshot).
AGE_AS_OF = date(2026, 2, 15)

# Depth-chart anchor is computed PER TEAM: the last daily ESPN crawl on or before
# that team's final 2025 game (game dates come from snap_counts pfr_game_id).
# Used ONLY for position resolution and as the last tie-break in the depth order;
# it is NOT the starter signal any more (see `primacy` below).
STARTER_WINDOW_DAYS = 35

# --------------------------------------------------------------------------
# Static identity data. Not derived data.
# --------------------------------------------------------------------------
TEAM_NAMES = {
    "ARI": "Arizona Cardinals",
    "ATL": "Atlanta Falcons",
    "BAL": "Baltimore Ravens",
    "BUF": "Buffalo Bills",
    "CAR": "Carolina Panthers",
    "CHI": "Chicago Bears",
    "CIN": "Cincinnati Bengals",
    "CLE": "Cleveland Browns",
    "DAL": "Dallas Cowboys",
    "DEN": "Denver Broncos",
    "DET": "Detroit Lions",
    "GB": "Green Bay Packers",
    "HOU": "Houston Texans",
    "IND": "Indianapolis Colts",
    "JAX": "Jacksonville Jaguars",
    "KC": "Kansas City Chiefs",
    "LA": "Los Angeles Rams",
    "LAC": "Los Angeles Chargers",
    "LV": "Las Vegas Raiders",
    "MIA": "Miami Dolphins",
    "MIN": "Minnesota Vikings",
    "NE": "New England Patriots",
    "NO": "New Orleans Saints",
    "NYG": "New York Giants",
    "NYJ": "New York Jets",
    "PHI": "Philadelphia Eagles",
    "PIT": "Pittsburgh Steelers",
    "SEA": "Seattle Seahawks",
    "SF": "San Francisco 49ers",
    "TB": "Tampa Bay Buccaneers",
    "TEN": "Tennessee Titans",
    "WAS": "Washington Commanders",
}

# QA_REPORT B4 -- league structure. Static NFL alignment, 2002-present.
DIVISIONS = {
    ("AFC", "East"):  ["BUF", "MIA", "NE", "NYJ"],
    ("AFC", "North"): ["BAL", "CIN", "CLE", "PIT"],
    ("AFC", "South"): ["HOU", "IND", "JAX", "TEN"],
    ("AFC", "West"):  ["DEN", "KC", "LAC", "LV"],
    ("NFC", "East"):  ["DAL", "NYG", "PHI", "WAS"],
    ("NFC", "North"): ["CHI", "DET", "GB", "MIN"],
    ("NFC", "South"): ["ATL", "CAR", "NO", "TB"],
    ("NFC", "West"):  ["ARI", "LA", "SEA", "SF"],
}
CONF_DIV = {}
for (_conf, _div), _teams in DIVISIONS.items():
    for _t in _teams:
        CONF_DIV[_t] = (_conf, _div)

# ----------------------------------------------------------------------
# QA_REPORT v2 -- result of the independent re-validation pass (2026-07-29).
# Emitted verbatim into league_raw_2026.json.qa.independentAudit so a consumer
# reads the audit and its residual caveats from the data file itself, not only
# from the markdown. Update alongside raw/QA_REPORT.md.
# ----------------------------------------------------------------------
QA_V2_AUDIT = {
    "auditedOn": "2026-07-29",
    "method": ("Re-derived independently of the builder: schema + type + range check on every "
               "team/player/season row, all roster and lineup gates recomputed from scratch, "
               "staffs decoded through a real Swift JSONDecoder against Domain/Enums/Scheme.swift, "
               "2025 skill-position stats reconciled field-by-field against "
               "_sources/stats/player_stats_reg_2025.csv."),
    "hardErrors": 0,
    "gateViolations": 0,
    "schemaErrors": 0,
    "statCrossCheck": {
        "fieldsCompared": 1231,
        "mismatches": 0,
        "source": "_sources/stats/player_stats_reg_2025.csv (nflverse REG 2025)",
        "note": ("14 skill players carry an all-zero 2025 row and have no nflverse REG row; "
                 "they appeared in a game without recording a stat. Zeros, not fabrication."),
    },
    "recomputedCoverage": {
        "note": ("Recomputed independently of _build_summary.json. `olRowsWithGamesPct` in the "
                 "build summary is an OR (gp or gs); the AND -- both populated -- is 2 points lower "
                 "and is the number a starts-based model should use."),
        "playerCount": 1807, "seasonRows": 7526, "seasonRowsExpected": 7903,
        "careerCoveragePct": 95.23, "gsFilledPct": 95.75, "gpFilledPct": 99.91,
        "olRows": 1283, "olRowsWithGpAndGsPct": 97.82,
        "snapShareNullRows": 477, "postseasonSubObjects": 2279,
        "jerseyFilledPct": 100.0, "collegeFilledPct": 99.72, "draftedPct": 74.05,
    },
    "intSplitVerified": {
        "thrown2025": 368, "caught2025": 365, "blendedV1": 785,
        "nflverseLeagueThrown2025": 380,
        "note": "QB rows keep `int` = thrown; every non-QB row uses `defInt`. 0 legacy `int` keys on non-QB rows.",
    },
    "residualCaveats": [
        ("DEPTH ORDER IS A ONE-SEASON VOLUME RANKING. `role`/`depthChartRank` rank players inside "
         "(team, position) by total 2025 regular-season snaps, so a durable fill-in outranks a "
         "franchise starter who missed half the year. 27 of 768 starter slots (3.5%, 21 teams) have "
         "a benched player who beat the listed starter on per-game snap share with a credible sample "
         "(>=5 starts, or >=8 games at >=55% share). Enumerated in qa.depthOrderSuspects. Neither a "
         "pure-rate nor a pure-volume rule is correct: rate alone moves 67 slots and breaks slots the "
         "volume rule gets right. Treat `role` as a hint and re-derive the depth chart from the "
         "generated ratings."),
        ("QB1 specifically: 5 of the 7 v1-flagged rooms are now right and CIN + WAS are still wrong "
         "(Flacco over Burrow, Mariota over Daniels). Both franchise QBs led on snap share and lost "
         "on volume, and neither was on IR at season end, so `injuredAtSeasonEnd` does not flag them."),
        ("2 jersey collisions (BUF #23, IND #17) are real re-issues after an IR placement; the "
         "importer must pick one."),
        ("5 players have `college: null`; 3 of them (Mailata, Stiggers, Smyth) never attended a US "
         "college and arguably want an explicit sentinel rather than null."),
        ("17 players have `seasons: []` -- no stat row, no snap and no PFR roster row in 2010-2025."),
    ],
    "verdict": "GO for Swift integration (anonymization + LeagueGenerator data path).",
}

# The 27 credible depth-order suspects found by the v2 audit: a benched player who
# beat the listed starter at the same position on 2025 per-game snap share with a
# real sample. Format: team, pos, bench player (share), listed starter (share).
QA_V2_DEPTH_SUSPECTS = [
    ("ARI", "CB",  "Garrett Williams", 0.817,   "Denzel Burke", 0.659),
    ("BUF", "OLB", "Shaq Thompson", 0.655,      "Dorian Williams", 0.470),
    ("CIN", "QB",  "Joe Burrow", 0.878,         "Joe Flacco", 0.778),
    ("DAL", "CB",  "Shavon Revel Jr.", 0.811,   "Reddy Steward", 0.535),
    ("DEN", "LG",  "Ben Powers", 0.865,         "Alex Palczewski", 0.611),
    ("DET", "CB",  "D.J. Reed", 0.820,          "Rock Ya-Sin", 0.569),
    ("DET", "DE",  "Marcus Davenport", 0.554,   "Al-Quadin Muhammad", 0.408),
    ("IND", "CB",  "Sauce Gardner", 0.795,      "Mekhi Blackmon", 0.689),
    ("IND", "DT",  "DeForest Buckner", 0.705,   "Adetomiwa Adebawore", 0.460),
    ("LA",  "CB",  "Quentin Lake", 0.938,       "Cobie Durant", 0.734),
    ("LAC", "LT",  "Bobby Hart", 0.821,         "Austin Deculus", 0.590),
    ("LAC", "MLB", "Marlowe Wax", 0.660,        "Troy Dye", 0.480),
    ("LAC", "OLB", "Khalil Mack", 0.601,        "Odafe Oweh", 0.479),
    ("MIA", "RT",  "Austin Jackson", 0.943,     "Larry Borom", 0.808),
    ("MIN", "RB",  "Aaron Jones", 0.551,        "Jordan Mason", 0.428),
    ("NO",  "C",   "Erik McCoy", 0.964,         "Luke Fortner", 0.687),
    ("NO",  "OLB", "Jonah Williams", 0.968,     "Carl Granderson", 0.692),
    ("NYJ", "CB",  "Tre Brown", 0.720,          "Qwan'tez Stiggers", 0.602),
    ("PIT", "FS",  "DeShon Elliott", 0.752,     "Chuck Clark", 0.537),
    ("SEA", "CB",  "Devon Witherspoon", 0.932,  "Josh Jobe", 0.769),
    ("SEA", "FS",  "Julian Love", 0.887,        "Ty Okada", 0.681),
    ("SF",  "DE",  "Mykel Williams", 0.666,     "Bryce Huff", 0.563),
    ("TB",  "RB",  "Bucky Irving", 0.616,       "Rachaad White", 0.511),
    ("TB",  "WR",  "Chris Godwin Jr.", 0.709,   "Tez Johnson", 0.471),
    ("TB",  "WR",  "Mike Evans", 0.656,         "Tez Johnson", 0.471),
    ("WAS", "QB",  "Jayden Daniels", 0.903,     "Marcus Mariota", 0.745),
    ("WAS", "WR",  "Treylon Burks", 0.601,      "Chris Moore", 0.486),
]


def depth_order_suspects():
    """qa.depthOrderSuspects payload."""
    return [{"team": t, "pos": p, "benched": b, "benchedSnapShare2025": bs,
             "listedStarter": s, "starterSnapShare2025": ss}
            for t, p, b, bs, s, ss in QA_V2_DEPTH_SUSPECTS]

# QA_REPORT B2 -- the coaching file's scheme vocabulary mapped onto the raw values
# of OffensiveScheme / DefensiveScheme in dynasty/Domain/Enums/Scheme.swift.
# This is a decision, recorded here so it is reviewable in one place.
OFF_SCHEME_ENUM = ["WestCoast", "AirRaid", "Spread", "PowerRun",
                   "Shanahan", "ProPassing", "RPO", "Option"]
DEF_SCHEME_ENUM = ["Base34", "Base43", "Cover3", "PressMan",
                   "Tampa2", "Multiple", "Hybrid"]
OFF_SCHEME_MAP = {
    "WideZone":   "Shanahan",    # outside/wide zone + play-action == the Shanahan tree
    "ProStyle":   "ProPassing",
    "Vertical":   "ProPassing",  # Coryell vertical passing game
    "SmashMouth": "PowerRun",
    "WestCoast":  "WestCoast",
    "Spread":     "Spread",
    "RPO":        "RPO",
    "AirRaid":    "AirRaid",
}
DEF_SCHEME_MAP = {
    "34":         "Base34",
    "43":         "Base43",
    "CoverThree": "Cover3",
    "ManPress":   "PressMan",
    "Nickel":     "Multiple",    # two-high nickel == a multiple sub-package base
    "Hybrid":     "Hybrid",
    "Tampa2":     "Tampa2",
}
# QA_REPORT B3 -- WideZone was assigned to 15/32 teams. Every one of those notes
# fields explicitly says "outside zone" / "wide zone" / "Shanahan tree" EXCEPT
# Dallas, whose prose says "zone-AND-GAP run game" (Schottenheimer is a gap-scheme
# coach). Only that one is overridden; the rest are genuinely the same family.
OFF_SCHEME_OVERRIDE = {
    "DAL": ("PowerRun", "notes say 'zone-and-gap run game' - Schottenheimer's gap-scheme "
                        "run game is not a wide-zone offense"),
}

# --------------------------------------------------------------------------
# Position vocabulary
# --------------------------------------------------------------------------
GAME_POSITIONS = {
    "QB", "RB", "FB", "WR", "TE",
    "LT", "LG", "C", "RG", "RT",
    "DE", "DT", "OLB", "MLB",
    "CB", "FS", "SS",
    "K", "P",
}
OL_POS = {"LT", "LG", "C", "RG", "RT"}
FRONT7 = {"DE", "DT", "OLB", "MLB"}
DB_POS = {"CB", "FS", "SS"}
OFFENSE_POS = {"QB", "RB", "FB", "WR", "TE"} | OL_POS
DEFENSE_POS = FRONT7 | DB_POS
ST_POS = {"K", "P"}

# depth-chart pos_abb -> game position, per base-defense family
DC_OFFENSE = {
    "QB": "QB", "RB": "RB", "FB": "FB", "WR": "WR", "TE": "TE",
    "LT": "LT", "LG": "LG", "C": "C", "RG": "RG", "RT": "RT",
}
DC_D43 = {
    "LDE": "DE", "RDE": "DE", "LDT": "DT", "RDT": "DT", "NT": "DT",
    "SLB": "OLB", "WLB": "OLB", "MLB": "MLB", "LILB": "MLB", "RILB": "MLB",
    "LCB": "CB", "RCB": "CB", "NB": "CB", "FS": "FS", "SS": "SS",
}
DC_D34 = {
    "LDE": "DE", "RDE": "DE", "NT": "DT", "LDT": "DT", "RDT": "DT",
    "SLB": "OLB", "WLB": "OLB", "LILB": "MLB", "RILB": "MLB", "MLB": "MLB",
    "LCB": "CB", "RCB": "CB", "NB": "CB", "FS": "FS", "SS": "SS",
}
DC_ST = {"PK": "K", "P": "P"}

STARTER_SLOTS_43 = ["LDE", "RDE", "LDT", "RDT", "SLB", "WLB", "MLB", "LCB", "RCB", "FS", "SS"]
STARTER_SLOTS_34 = ["LDE", "RDE", "NT", "SLB", "WLB", "LILB", "RILB", "LCB", "RCB", "FS", "SS"]
STARTER_SLOTS_OFF = ["QB", "RB", "TE", "LT", "LG", "C", "RG", "RT"]
N_STARTING_WR = 3
STARTER_SLOTS_ST = ["PK", "P"]

RW_FALLBACK = {
    "QB": "QB", "RB": "RB", "FB": "FB", "WR": "WR", "TE": "TE", "C": "C",
    "DT": "DT", "NT": "DT", "DE": "DE", "OLB": "OLB", "ILB": "MLB", "MLB": "MLB",
    "CB": "CB", "FS": "FS", "SS": "SS", "K": "K", "P": "P",
}

MIN_ROSTER, MAX_ROSTER = 48, 58
MIN_STARTERS, MAX_STARTERS = 20, 26
ROTATION_SNAP_SHARE = 0.20
MAX_IR = 3

# How many starters a base lineup holds at each position. The depth order is
# ranked inside team+position, and the top `quota` at each position ARE the
# starters -- which is what makes 11 offensive + 11 defensive starters structural
# rather than something that has to be patched up afterwards.
STARTER_QUOTA_OFF = {"QB": 1, "RB": 1, "WR": 3, "TE": 1,
                     "LT": 1, "LG": 1, "C": 1, "RG": 1, "RT": 1}
STARTER_QUOTA_ST = {"K": 1, "P": 1}
STARTER_QUOTA_43 = {"DE": 2, "DT": 2, "OLB": 2, "MLB": 1, "CB": 2, "FS": 1, "SS": 1}
STARTER_QUOTA_34 = {"DE": 2, "DT": 1, "OLB": 2, "MLB": 2, "CB": 2, "FS": 1, "SS": 1}

# If a base-lineup slot has no player at all, borrow the best surplus body from
# the mirrored position rather than shipping a 10-man lineup (QA_REPORT M3: LAC
# had two LTs and no RT). The move is recorded in that player's `notes`.
POSITION_SIBLINGS = {
    "LT": ["RT"], "RT": ["LT"], "LG": ["RG"], "RG": ["LG"],
    "FS": ["SS"], "SS": ["FS"], "MLB": ["OLB"], "OLB": ["MLB"],
    "DE": ["DT"], "DT": ["DE"], "CB": ["FS", "SS"],
}


def starter_quota(base_def):
    q = dict(STARTER_QUOTA_OFF)
    q.update(STARTER_QUOTA_ST)
    q.update(STARTER_QUOTA_34 if base_def == "Base 3-4 D" else STARTER_QUOTA_43)
    return q


SOURCES = [
    "https://github.com/nflverse/nflverse-data/releases/download/weekly_rosters/roster_weekly_2025.csv",
    "https://github.com/nflverse/nflverse-data/releases/download/rosters/roster_2025.csv",
    "https://github.com/nflverse/nflverse-data/releases/download/players/players.csv",
    "https://github.com/nflverse/nflverse-data/releases/download/depth_charts/depth_charts_2025.csv",
    "https://github.com/nflverse/nflverse-data/releases/download/snap_counts/snap_counts_<2013-2025>.csv",
    "https://github.com/nflverse/nflverse-data/releases/download/pfr_advstats/pfr_rosters.csv",
    "https://github.com/nflverse/nflverse-data/releases/download/pfr_advstats/advstats_season_def.csv",
    "https://github.com/nflverse/nflverse-data/releases/download/pfr_advstats/advstats_season_rush.csv",
    "https://github.com/nflverse/nflverse-data/releases/download/pfr_advstats/advstats_season_rec.csv",
    "https://github.com/nflverse/nflverse-data/releases/download/draft_picks/draft_picks.csv",
    "https://github.com/nflverse/nflverse-data/releases/download/stats_player/stats_player_reg_<2010-2025>.csv",
    "https://github.com/nflverse/nflverse-data/releases/download/stats_player/stats_player_regpost_<2010-2025>.csv",
    "https://en.wikipedia.org/wiki/2025_NFL_season",
]

SCHEMA_NOTES = {
    "schemaVersion": 2,
    "role": ("Depth order ENTERING 2026, not a week-21 photograph. Players are ranked "
             "inside (team, position) by season-long 2025 primacy -- regular-season "
             "snaps on their own side of the ball, then position volume (pass attempts / "
             "carries+targets / targets / tackles / kicks / punts), then days held ESPN "
             "pos_rank 1 in the closing 35 days. The top `starterQuota[pos]` at each "
             "position are `starter`; the rest fall to rotation / backup / depth by snap "
             "share. A franchise starter who finished the year on IR outranks the "
             "fill-in who replaced him, because the season totals say so."),
    "depthChartRank": "1..n inside (team, position), 1 = the projected 2026 starter.",
    "injuredAtSeasonEnd": ("true if the player was on reserve/injured (roster status RES) "
                           "at his team's final 2025 game. This replaces the old "
                           "`role: \"ir\"`, which conflated availability with depth."),
    "roleVocabulary": ["starter", "rotation", "backup", "depth"],
    "seasons": ("REGULAR SEASON only (nflverse season_type REG). Postseason production, "
                "where it exists, is a separate optional `post` sub-object on the same "
                "row, derived as (REG+POST) - REG. Up to 8 most recent seasons in which "
                "the player actually appeared, anywhere in 2010-2025."),
    "gp": ("Games played. Source precedence: PFR team roster table G (2010-2022) -> "
           "games with >=1 recorded snap in PFR snap counts (2013-2025) -> nflverse "
           "`games` (non-OL only; it counts games with a recorded STAT and undercounts "
           "linemen by ~10-12 a season) -> null."),
    "gs": ("Games started. Source precedence recorded per row in `gsSrc`: "
           "`pfrRoster` = PFR team roster table GS (2010-2022, authoritative, all "
           "positions); `pfrAdvStats` = PFR advanced season tables GS (2018-2025, "
           "skill + defense only); `snapStart50` = DERIVED PROXY, offensive linemen "
           "only, counting regular-season games in which the player took >=50% of his "
           "team's offensive snaps -- an OL is on the field for either ~all or ~none of "
           "a game, so this is near-exact, but it is a proxy and is labelled as one; "
           "`pfrConventionKP` = 0 for a kicker or punter who played, which is what PFR "
           "records for every one of the 1827 K/P team-seasons on disk without "
           "exception; null = genuinely underivable from the sources on disk."),
    "snapShare": ("Mean share of his side's snaps in the regular-season games he "
                  "appeared in, 0-1, from PFR snap counts. null before 2013."),
    "statKeys": {
        "QB": ("att comp yds td int sacked rating rushAtt rushYds rushTd -- on a QB row "
               "`int` is INTERCEPTIONS THROWN and `td` is PASSING touchdowns."),
        "RB/FB": "rushAtt rushYds rushTd rec recYds recTd fum",
        "WR/TE": "rec tgt recYds recTd rushAtt rushYds",
        "DE/DT/OLB/MLB": ("tackles tfl sacks ff pd defInt defTd -- `defInt` is "
                          "INTERCEPTIONS CAUGHT and `defTd` is a DEFENSIVE touchdown. "
                          "The polysemous `int`/`td` keys of v1 are gone."),
        "CB/FS/SS": "tackles defInt pd defTd sacks",
        "LT/LG/C/RG/RT": ("snaps pen penYds fum -- linemen record almost nothing in the "
                          "play-by-play, so the production signal for them is snaps and "
                          "the row-level gp/gs/snapShare."),
        "K": "fgm fga long xpm xpa",
        "P": "punts avg in20",
    },
    "scheme": ("coaching_staffs_2026.json carries both the original compiled guess "
               "(offSchemeGuess / defSchemeGuess, its own vocabulary) and offScheme / "
               "defScheme, which are raw values of OffensiveScheme / DefensiveScheme in "
               "dynasty/Domain/Enums/Scheme.swift and decode 32/32."),
    "anonymisation": ("Real names. Per docs/ANONYMIZATION_SPEC.md 6.5 this tree must "
                      "never enter a shipping target's resources."),
}


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
def need(path: str) -> str:
    if not os.path.exists(path):
        sys.exit(f"FATAL: required local source missing: {path}")
    if os.path.getsize(path) < 1024:
        sys.exit(f"FATAL: local source looks truncated/error page: {path}")
    return path


def read_csv(path: str):
    with open(need(path), newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            yield row


def i(v, default=None):
    if v is None:
        return default
    v = str(v).strip()
    if v == "" or v.upper() in ("NA", "NAN", "NONE"):
        return default
    try:
        return int(float(v))
    except ValueError:
        return default


def f(v, default=None):
    if v is None:
        return default
    v = str(v).strip()
    if v == "" or v.upper() in ("NA", "NAN", "NONE"):
        return default
    try:
        return float(v)
    except ValueError:
        return default


def age_on(birth: str, ref: date):
    if not birth:
        return None
    try:
        y, m, d = (int(x) for x in birth.split("-")[:3])
        b = date(y, m, d)
    except (ValueError, TypeError):
        return None
    return ref.year - b.year - ((ref.month, ref.day) < (b.month, b.day))


def passer_rating(comp, att, yds, td, ints):
    """Standard NFL passer rating. Deterministic derivation, not an estimate."""
    if not att:
        return None
    a = max(0.0, min(2.375, ((comp / att) - 0.3) * 5))
    b = max(0.0, min(2.375, ((yds / att) - 3) * 0.25))
    c = max(0.0, min(2.375, (td / att) * 20))
    d = max(0.0, min(2.375, 2.375 - (ints / att * 25)))
    return round((a + b + c + d) / 6 * 100, 1)


# --------------------------------------------------------------------------
# 1. players.csv -- master bio table
# --------------------------------------------------------------------------
def load_players():
    out = {}
    for r in read_csv(os.path.join(SRC, "players.csv")):
        if r["gsis_id"]:
            out[r["gsis_id"]] = r
    if len(out) < 20000:
        sys.exit(f"FATAL: players.csv only {len(out)} rows")
    return out


# --------------------------------------------------------------------------
# 2. roster_weekly_2025.csv -- anchor roster;  roster_2025.csv -- jersey numbers
# --------------------------------------------------------------------------
def load_rosters():
    rows = list(read_csv(os.path.join(SRC, "roster_weekly_2025.csv")))
    if len(rows) < 40000:
        sys.exit(f"FATAL: roster_weekly_2025.csv only {len(rows)} rows")

    anchor_week = defaultdict(int)
    for r in rows:
        if r["status"] == "ACT":
            anchor_week[r["team"]] = max(anchor_week[r["team"]], i(r["week"], 0))

    last_game_type = {}
    for r in rows:
        if i(r["week"], 0) == anchor_week[r["team"]]:
            last_game_type[r["team"]] = r["game_type"]

    active = defaultdict(list)
    reserve = defaultdict(list)
    for r in rows:
        if i(r["week"], 0) != anchor_week[r["team"]]:
            continue
        if r["status"] in ("ACT", "INA"):
            active[r["team"]].append(r)
        elif r["status"] == "RES":
            reserve[r["team"]].append(r)

    return anchor_week, last_game_type, active, reserve


def load_jerseys():
    """
    (gsis_id, team) -> jersey number and gsis_id -> jersey number, from the season
    roster release. The team key matters: a player who finished the year on another
    club's practice squad carries THAT club's number in the season file (Shane
    Buechele is #17 at KC and #6 at BUF), so the per-team lookup is tried first.
    """
    by_team, any_team = {}, {}
    n = 0
    for r in read_csv(os.path.join(SRC, "roster_2025.csv")):
        gid = r.get("gsis_id", "")
        j = i(r.get("jersey_number"))
        if not gid or j is None:
            continue
        n += 1
        wk = i(r.get("week"), 0)
        k = (gid, r.get("team", ""))
        if k not in by_team or wk >= by_team[k][0]:
            by_team[k] = (wk, j)
        if gid not in any_team or wk >= any_team[gid][0]:
            any_team[gid] = (wk, j)
    if n < 2000:
        sys.exit(f"FATAL: roster_2025.csv only {n} usable jersey rows")
    return ({k: v[1] for k, v in by_team.items()},
            {k: v[1] for k, v in any_team.items()})


# --------------------------------------------------------------------------
# 3. depth_charts_2025.csv
# --------------------------------------------------------------------------
def load_last_game_dates(snap2025_game_dates):
    if len(snap2025_game_dates) != 32:
        sys.exit(f"FATAL: derived final-game dates for {len(snap2025_game_dates)} teams, expected 32")
    return snap2025_game_dates


def load_depth_charts(last_game):
    rows = list(read_csv(os.path.join(SRC, "depth_charts_2025.csv")))
    if len(rows) < 400000:
        sys.exit(f"FATAL: depth_charts_2025.csv only {len(rows)} rows")

    dts_by_team = defaultdict(set)
    for r in rows:
        dts_by_team[r["team"]].add(r["dt"])
    anchor_dt = {}
    for team in TEAM_NAMES:
        cand = sorted(d for d in dts_by_team[team] if d[:10] <= last_game[team])
        if not cand:
            sys.exit(f"FATAL: no depth-chart snapshot for {team} on/before {last_game[team]}")
        anchor_dt[team] = cand[-1]

    window_start = {}
    for team in TEAM_NAMES:
        y, m, d = (int(x) for x in last_game[team].split("-"))
        window_start[team] = (date(y, m, d) - timedelta(days=STARTER_WINDOW_DAYS)).isoformat()

    anchor_rows = defaultdict(lambda: defaultdict(list))
    latest = defaultdict(lambda: defaultdict(dict))
    ever_rank1 = defaultdict(set)
    grp_count = defaultdict(Counter)
    window_rows = defaultdict(list)

    for r in rows:
        team, gid, grp = r["team"], r["gsis_id"], r["pos_grp"]
        if not gid or team not in anchor_dt or r["dt"] > anchor_dt[team]:
            continue
        prev = latest[team][gid].get(grp)
        if prev is None or r["dt"] > prev["dt"]:
            latest[team][gid][grp] = r
        if r["dt"] == anchor_dt[team]:
            anchor_rows[team][gid].append(r)
        if r["dt"][:10] >= window_start[team]:
            window_rows[team].append(r)
            grp_count[team][grp] += 1
        if grp != "Special Teams" and i(r["pos_rank"], 9) == 1:
            ever_rank1[team].add(gid)

    base_def = {}
    for team in TEAM_NAMES:
        c = grp_count[team]
        n34, n43 = c.get("Base 3-4 D", 0), c.get("Base 4-3 D", 0)
        base_def[team] = "Base 3-4 D" if n34 > n43 else "Base 4-3 D"

    return base_def, anchor_rows, latest, anchor_dt, ever_rank1, window_rows


# --------------------------------------------------------------------------
# 4. snap counts 2013-2025 -- games played, snap share, OL start proxy
# --------------------------------------------------------------------------
def _blank_snap():
    return {"games": 0, "off": 0, "def": 0, "st": 0,
            "off_g": 0, "off_pct": 0.0, "def_g": 0, "def_pct": 0.0,
            "start50": 0}


def load_snaps():
    """
    (pfr_player_id, season) -> {"reg": {...}, "post": {...}}
    Also returns team -> ISO date of its final 2025 game (any game type).
    """
    agg = defaultdict(lambda: {"reg": _blank_snap(), "post": _blank_snap()})
    last_game = {}
    total_rows = 0
    for y in SNAP_YEARS:
        path = os.path.join(SNAPS_DIR, f"snap_counts_{y}.csv")
        n = 0
        for r in read_csv(path):
            pid = r["pfr_player_id"]
            n += 1
            if y == 2025:
                g = r["pfr_game_id"]
                if len(g) >= 8 and g[:8].isdigit():
                    d = f"{g[0:4]}-{g[4:6]}-{g[6:8]}"
                    t = r["team"]
                    if d > last_game.get(t, ""):
                        last_game[t] = d
            if not pid:
                continue
            bucket = "reg" if r["game_type"] == "REG" else "post"
            a = agg[(pid, y)][bucket]
            off, dfn, st = (i(r["offense_snaps"], 0), i(r["defense_snaps"], 0),
                            i(r["st_snaps"], 0))
            if off + dfn + st > 0:
                a["games"] += 1
            a["off"] += off
            a["def"] += dfn
            a["st"] += st
            opct = f(r["offense_pct"], 0.0) or 0.0
            dpct = f(r["defense_pct"], 0.0) or 0.0
            if off > 0:
                a["off_g"] += 1
                a["off_pct"] += opct
                if opct >= 0.5:
                    a["start50"] += 1
            if dfn > 0:
                a["def_g"] += 1
                a["def_pct"] += dpct
        if n < 20000:
            sys.exit(f"FATAL: {path} only {n} rows")
        total_rows += n
    print(f"  snap_counts: {total_rows} rows over {len(SNAP_YEARS)} seasons")
    return agg, last_game


def snap_share(a):
    """Mean share of his own side's snaps, or None if he took none."""
    if a is None:
        return None
    off_mean = a["off_pct"] / a["off_g"] if a["off_g"] else None
    def_mean = a["def_pct"] / a["def_g"] if a["def_g"] else None
    if a["off"] >= a["def"] and off_mean is not None:
        return round(off_mean, 3)
    if def_mean is not None:
        return round(def_mean, 3)
    if off_mean is not None:
        return round(off_mean, 3)
    return None


# --------------------------------------------------------------------------
# 5. PFR games / games started
# --------------------------------------------------------------------------
def season_games(y):
    """Regular-season length. 16 through 2020, 17 from 2021."""
    return 17 if y >= 2021 else 16


def load_pfr_rosters():
    """
    (pfr_player_id, season) -> {'g': int|None, 'gs': int|None}.

    pfr_rosters.csv carries the SAME team-season row twice for teams whose PFR and
    NFL abbreviations differ (JAX/JAC, LAR/LA, ...), so a naive sum doubles Calais
    Campbell's 2018 to 32 games. Dedupe per (player, season, pfr team) first, then
    sum across genuinely different teams, then clamp to the season length.
    """
    per_team = defaultdict(lambda: {"g": None, "gs": None})
    n = 0
    for r in read_csv(os.path.join(GS_DIR, "pfr_rosters.csv")):
        pid = r["pfr_player_id"]
        y = i(r["season"])
        if not pid or y is None or y < CAREER_YEARS[0]:
            continue
        n += 1
        e = per_team[(pid, y, r["pfr"])]
        g, gs = i(r["g"]), i(r["gs"])
        if g is not None and (e["g"] is None or g > e["g"]):
            e["g"] = g
        if gs is not None and (e["gs"] is None or gs > e["gs"]):
            e["gs"] = gs

    out = defaultdict(lambda: {"g": None, "gs": None})
    for (pid, y, _tm), e in per_team.items():
        o = out[(pid, y)]
        if e["g"] is not None:
            o["g"] = (o["g"] or 0) + e["g"]
        if e["gs"] is not None:
            o["gs"] = (o["gs"] or 0) + e["gs"]
    clamped = 0
    for (pid, y), o in out.items():
        cap = season_games(y)
        for k in ("g", "gs"):
            if o[k] is not None and o[k] > cap:
                o[k] = cap
                clamped += 1
    if n < 20000:
        sys.exit(f"FATAL: gs/pfr_rosters.csv only {n} rows in window")
    print(f"  pfr_rosters: {n} rows (<= {PFR_ROSTER_MAX_YEAR}) -> {len(out)} player-seasons "
          f"({len(per_team)} player-team-seasons, {clamped} clamped to season length)")
    return out


def load_advstats_gs():
    """(pfr_id, season) -> games started, max over the def/rush/rec season tables."""
    out = {}
    n = 0
    for kind in ("def", "rush", "rec"):
        path = os.path.join(GS_DIR, f"advstats_season_{kind}.csv")
        for r in read_csv(path):
            pid = (r.get("pfr_id") or "").strip()
            y = i(r.get("season"))
            gs = i(r.get("gs"))
            if not pid or y is None or gs is None:
                continue
            n += 1
            k = (pid, y)
            if k not in out or gs > out[k]:
                out[k] = gs
    if n < 10000:
        sys.exit(f"FATAL: advstats season tables only {n} usable rows")
    print(f"  advstats: {n} rows -> {len(out)} player-seasons with GS")
    return out


# --------------------------------------------------------------------------
# 6. draft_picks.csv
# --------------------------------------------------------------------------
def load_draft():
    by_gsis = {}
    by_namecoll = {}
    n = 0
    for r in read_csv(os.path.join(SRC, "draft_picks.csv")):
        season = i(r["season"])
        if season is None or season > 2025:
            continue
        n += 1
        rec = {"year": season, "round": i(r["round"]), "pick": i(r["pick"])}
        if r["gsis_id"]:
            by_gsis[r["gsis_id"]] = rec
        key = (r["pfr_player_name"].strip().lower(), (r["college"] or "").strip().lower())
        by_namecoll.setdefault(key, rec)
    if n < 10000:
        sys.exit(f"FATAL: draft_picks.csv only {n} rows <= 2025")
    return by_gsis, by_namecoll


# --------------------------------------------------------------------------
# 7. player stats 2010-2025, REG and REG+POST kept apart
# --------------------------------------------------------------------------
# Every numeric column project_stats() touches, so a POST row can be derived as
# (REG+POST) - REG. `fg_long` / `pt_long` are maxima and cannot be differenced.
NUM_COLS = [
    "games", "completions", "attempts", "passing_yards", "passing_tds",
    "passing_interceptions", "sacks_suffered", "carries", "rushing_yards",
    "rushing_tds", "receptions", "targets", "receiving_yards", "receiving_tds",
    "fumbles_total", "def_tackles_solo", "def_tackle_assists",
    "def_tackles_for_loss", "def_fumbles_forced", "def_pass_defended",
    "def_interceptions", "def_tds", "fg_made", "fg_att", "pat_made", "pat_att",
    "pt_att", "pt_yards", "pt_inside_20", "penalties", "penalty_yards",
]
FLOAT_COLS = ["def_sacks"]


def load_stats():
    """
    reg[pid][year]     -> the REG row  (nflverse stats_player_reg)
    regpost[pid][year] -> the REG+POST / REG / POST row (stats_player_regpost)
    """
    reg = defaultdict(dict)
    regpost = defaultdict(dict)
    nreg = nrp = 0
    for y in CAREER_YEARS:
        p_reg = os.path.join(STATS_DIR, f"player_stats_reg_{y}.csv")
        rows = list(read_csv(p_reg))
        if len(rows) < 1000:
            sys.exit(f"FATAL: {p_reg} only {len(rows)} rows")
        for r in rows:
            if r["season_type"] != "REG":
                sys.exit(f"FATAL: {p_reg} contains season_type {r['season_type']}")
            if r["player_id"]:
                reg[r["player_id"]][y] = r
                nreg += 1

        p_rp = os.path.join(STATS_DIR, f"player_stats_{y}.csv")
        rows = list(read_csv(p_rp))
        if len(rows) < 1000:
            sys.exit(f"FATAL: {p_rp} only {len(rows)} rows")
        rank = {"REG+POST": 3, "POST": 2, "REG": 1}
        for r in rows:
            pid = r["player_id"]
            if not pid:
                continue
            cur = regpost[pid].get(y)
            if cur is None or rank.get(r["season_type"], 0) > rank.get(cur["season_type"], 0):
                regpost[pid][y] = r
                nrp += 1
    print(f"  stats: {nreg} REG rows / {nrp} REG+POST rows over {len(CAREER_YEARS)} seasons")
    return reg, regpost


def post_row(rp, rg):
    """(REG+POST) - REG, as a row-shaped dict. None when there is no postseason."""
    if rp is None:
        return None
    st = rp["season_type"]
    if st == "REG":
        return None
    if st == "POST":
        return rp
    if rg is None:
        return rp          # REG+POST with no REG row == postseason only
    out = {"recent_team": rp.get("recent_team"), "season_type": "POST",
           "fg_long": "", "pt_long": ""}
    any_pos = False
    for c in NUM_COLS:
        v = i(rp.get(c), 0) - i(rg.get(c), 0)
        if v < 0:
            v = 0
        if v:
            any_pos = True
        out[c] = v
    for c in FLOAT_COLS:
        v = round((f(rp.get(c), 0.0) or 0.0) - (f(rg.get(c), 0.0) or 0.0), 1)
        out[c] = max(0.0, v)
    if i(out.get("games"), 0) <= 0 and not any_pos:
        return None
    return out


# --------------------------------------------------------------------------
# Stat projection
# --------------------------------------------------------------------------
def zero_stats(pos):
    if pos in OL_POS:
        return {"snaps": None, "pen": 0, "penYds": 0, "fum": 0}
    if pos == "QB":
        return {"att": 0, "comp": 0, "yds": 0, "td": 0, "int": 0, "sacked": 0,
                "rushAtt": 0, "rushYds": 0, "rushTd": 0, "rating": None}
    if pos in ("RB", "FB"):
        return {"rushAtt": 0, "rushYds": 0, "rushTd": 0, "rec": 0, "recYds": 0,
                "recTd": 0, "fum": 0}
    if pos in ("WR", "TE"):
        return {"rec": 0, "tgt": 0, "recYds": 0, "recTd": 0, "rushAtt": 0, "rushYds": 0}
    if pos in FRONT7:
        return {"tackles": 0, "tfl": 0, "sacks": 0, "ff": 0, "pd": 0,
                "defInt": 0, "defTd": 0}
    if pos in DB_POS:
        return {"tackles": 0, "defInt": 0, "pd": 0, "defTd": 0, "sacks": 0}
    if pos == "K":
        return {"fgm": 0, "fga": 0, "long": None, "xpm": 0, "xpa": 0}
    if pos == "P":
        return {"punts": 0, "avg": None, "in20": 0}
    return {}


def project_stats(pos, r, ol_snaps=None):
    """Map an nflverse stats row onto the schema's per-position stat keys."""
    if pos in OL_POS:
        if r is None:
            return {"snaps": ol_snaps, "pen": None, "penYds": None, "fum": None}
        return {
            "snaps": ol_snaps,
            "pen": i(r.get("penalties"), 0),
            "penYds": i(r.get("penalty_yards"), 0),
            "fum": i(r.get("fumbles_total"), 0),
        }
    if r is None:
        return zero_stats(pos)

    if pos == "QB":
        att = i(r.get("attempts"), 0)
        comp = i(r.get("completions"), 0)
        yds = i(r.get("passing_yards"), 0)
        td = i(r.get("passing_tds"), 0)
        ints = i(r.get("passing_interceptions"), 0)
        return {
            "att": att, "comp": comp, "yds": yds, "td": td, "int": ints,
            "sacked": i(r.get("sacks_suffered"), 0),
            "rushAtt": i(r.get("carries"), 0),
            "rushYds": i(r.get("rushing_yards"), 0),
            "rushTd": i(r.get("rushing_tds"), 0),
            "rating": passer_rating(comp, att, yds, td, ints),
        }

    if pos in ("RB", "FB"):
        return {
            "rushAtt": i(r.get("carries"), 0),
            "rushYds": i(r.get("rushing_yards"), 0),
            "rushTd": i(r.get("rushing_tds"), 0),
            "rec": i(r.get("receptions"), 0),
            "recYds": i(r.get("receiving_yards"), 0),
            "recTd": i(r.get("receiving_tds"), 0),
            "fum": i(r.get("fumbles_total"), 0),
        }

    if pos in ("WR", "TE"):
        return {
            "rec": i(r.get("receptions"), 0),
            "tgt": i(r.get("targets"), 0),
            "recYds": i(r.get("receiving_yards"), 0),
            "recTd": i(r.get("receiving_tds"), 0),
            "rushAtt": i(r.get("carries"), 0),
            "rushYds": i(r.get("rushing_yards"), 0),
        }

    tackles = i(r.get("def_tackles_solo"), 0) + i(r.get("def_tackle_assists"), 0)
    if pos in FRONT7:
        return {
            "tackles": tackles,
            "tfl": i(r.get("def_tackles_for_loss"), 0),
            "sacks": round(f(r.get("def_sacks"), 0.0) or 0.0, 1),
            "ff": i(r.get("def_fumbles_forced"), 0),
            "pd": i(r.get("def_pass_defended"), 0),
            "defInt": i(r.get("def_interceptions"), 0),
            "defTd": i(r.get("def_tds"), 0),
        }
    if pos in DB_POS:
        return {
            "tackles": tackles,
            "defInt": i(r.get("def_interceptions"), 0),
            "pd": i(r.get("def_pass_defended"), 0),
            "defTd": i(r.get("def_tds"), 0),
            "sacks": round(f(r.get("def_sacks"), 0.0) or 0.0, 1),
        }

    if pos == "K":
        return {
            "fgm": i(r.get("fg_made"), 0),
            "fga": i(r.get("fg_att"), 0),
            "long": i(r.get("fg_long")),
            "xpm": i(r.get("pat_made"), 0),
            "xpa": i(r.get("pat_att"), 0),
        }
    if pos == "P":
        punts = i(r.get("pt_att"), 0)
        yards = i(r.get("pt_yards"), 0)
        return {
            "punts": punts,
            "avg": round(yards / punts, 1) if punts else None,
            "in20": i(r.get("pt_inside_20"), 0),
        }
    return {}


def volume_for(pos, r):
    """Position-appropriate season volume, the secondary depth-order key."""
    if r is None:
        return 0
    if pos == "QB":
        return i(r.get("attempts"), 0)
    if pos in ("RB", "FB"):
        return i(r.get("carries"), 0) + i(r.get("targets"), 0)
    if pos in ("WR", "TE"):
        return i(r.get("targets"), 0) + i(r.get("carries"), 0)
    if pos in DEFENSE_POS:
        return (i(r.get("def_tackles_solo"), 0) + i(r.get("def_tackle_assists"), 0)
                + i(r.get("def_pass_defended"), 0) + i(r.get("def_interceptions"), 0))
    if pos == "K":
        return i(r.get("fg_att"), 0) + i(r.get("pat_att"), 0)
    if pos == "P":
        return i(r.get("pt_att"), 0)
    return 0


# --------------------------------------------------------------------------
# Position resolution
# --------------------------------------------------------------------------
def dc_map_for(grp, base_def):
    if grp == "3WR 1TE":
        return DC_OFFENSE
    if grp == "Base 4-3 D":
        return DC_D43
    if grp == "Base 3-4 D":
        return DC_D34
    if grp == "Special Teams":
        return DC_ST
    return {}


def resolve_position(rw, team, base_def, latest_dc, anchor_dc, tackle_alt, guard_alt, safety_alt):
    gid = rw["gsis_id"]
    rw_pos = rw["position"]
    if rw_pos == "LS":
        return None, "ls"
    if rw_pos == "K":
        return "K", "roster"
    if rw_pos == "P":
        return "P", "roster"

    offense = rw_pos in ("QB", "RB", "WR", "TE", "OL", "FB")
    want_grps = ["3WR 1TE"] if offense else [base_def, "Base 3-4 D" if base_def == "Base 4-3 D" else "Base 4-3 D"]

    cands = []
    for r in anchor_dc.get(team, {}).get(gid, []):
        if r["pos_grp"] in want_grps:
            m = dc_map_for(r["pos_grp"], base_def)
            p = m.get(r["pos_abb"])
            if p:
                cands.append((want_grps.index(r["pos_grp"]), i(r["pos_rank"], 9),
                              i(r["pos_slot"], 99), p))
    if cands:
        cands.sort()
        return cands[0][3], "depth_anchor"

    best = None
    for grp in want_grps:
        r = latest_dc.get(team, {}).get(gid, {}).get(grp)
        if r is None:
            continue
        p = dc_map_for(grp, base_def).get(r["pos_abb"])
        if p and (best is None or r["dt"] > best[0]):
            best = (r["dt"], p)
    if best:
        return best[1], "depth_season"

    dcp = rw["depth_chart_position"]
    ngs = rw["ngs_position"]
    if dcp == "T":
        return (tackle_alt(), "fallback")
    if dcp == "G":
        return (guard_alt(), "fallback")
    if dcp in ("S", "DB"):
        if ngs == "SLOT_CB":
            return "CB", "fallback"
        return (safety_alt(), "fallback")
    if dcp == "LB":
        return ("OLB" if ngs == "EDGE" else "MLB"), "fallback"
    p = RW_FALLBACK.get(dcp)
    if p:
        return p, "fallback"
    coarse = {"QB": "QB", "RB": "RB", "WR": "WR", "TE": "TE", "K": "K", "P": "P"}.get(rw_pos)
    if coarse:
        return coarse, "fallback"
    if rw_pos == "OL":
        return tackle_alt(), "fallback"
    if rw_pos == "DL":
        return "DT", "fallback"
    if rw_pos == "LB":
        return "MLB", "fallback"
    if rw_pos == "DB":
        return "CB", "fallback"
    return None, "unresolved"


def rank1_days(team, base_def, window_rows):
    """gsis id -> number of closing-window days he held a base-lineup slot at rank 1."""
    def_slots = STARTER_SLOTS_34 if base_def == "Base 3-4 D" else STARTER_SLOTS_43
    days = Counter()
    for r in window_rows.get(team, []):
        grp, abb, rank, gid = r["pos_grp"], r["pos_abb"], i(r["pos_rank"], 99), r["gsis_id"]
        if not gid:
            continue
        if grp == "3WR 1TE" and abb == "WR":
            if rank <= N_STARTING_WR:
                days[gid] += 1
            continue
        if rank != 1:
            continue
        if ((grp == "3WR 1TE" and abb in STARTER_SLOTS_OFF)
                or (grp == base_def and abb in def_slots)
                or (grp == "Special Teams" and abb in STARTER_SLOTS_ST)):
            days[gid] += 1
    return days


# --------------------------------------------------------------------------
# Coaching staffs -- re-key + scheme mapping (QA_REPORT B1/B2/B3)
# --------------------------------------------------------------------------
def normalise_staffs(base_def):
    path = os.path.join(RAW, "coaching_staffs_2026.json")
    with open(need(path), encoding="utf-8") as fh:
        doc = json.load(fh)

    staffs = doc.get("staffs") or {}
    renamed = []
    if "LAR" in staffs and "LA" not in staffs:
        staffs["LA"] = staffs.pop("LAR")
        renamed.append("LAR->LA (applied this run)")
    elif "LA" in staffs and "LAR" not in staffs:
        renamed.append("LAR->LA (already normalised in the file on disk)")

    missing = sorted(set(TEAM_NAMES) - set(staffs))
    extra = sorted(set(staffs) - set(TEAM_NAMES))
    if missing or extra:
        sys.exit(f"FATAL: coaching staff keys off: missing={missing} extra={extra}")

    off_hist, def_hist, overrides = Counter(), Counter(), []
    for abbr in sorted(staffs):
        s = staffs[abbr]
        og, dg = s.get("offSchemeGuess"), s.get("defSchemeGuess")
        off = OFF_SCHEME_MAP.get(og)
        dfn = DEF_SCHEME_MAP.get(dg)
        if off is None or dfn is None:
            sys.exit(f"FATAL: no scheme mapping for {abbr}: off={og!r} def={dg!r}")
        if abbr in OFF_SCHEME_OVERRIDE:
            new, why = OFF_SCHEME_OVERRIDE[abbr]
            overrides.append(f"{abbr}: {off} -> {new} ({why})")
            off = new
        s["offScheme"] = off
        s["defScheme"] = dfn
        s["baseDefense2025"] = base_def.get(abbr)
        off_hist[off] += 1
        def_hist[dfn] += 1
        # keep the original guess visible, and say what happened, inside notes
        prov = (f"[scheme] offScheme={off} / defScheme={dfn} are the "
                f"Domain/Enums/Scheme.swift raw values; compiled guesses were "
                f"offSchemeGuess={og} / defSchemeGuess={dg}.")
        if abbr in OFF_SCHEME_OVERRIDE:
            prov += " Offense re-graded from the notes: " + OFF_SCHEME_OVERRIDE[abbr][1] + "."
        base = (s.get("notes") or "").split(" [scheme] ")[0].rstrip()
        s["notes"] = f"{base} {prov}" if base else prov

    doc["staffs"] = staffs
    doc["schemeEnums"] = {"off": OFF_SCHEME_ENUM, "def": DEF_SCHEME_ENUM,
                          "source": "dynasty/dynasty/Domain/Enums/Scheme.swift"}
    doc["schemeGuessVocabulary"] = {
        "off": sorted(OFF_SCHEME_MAP), "def": sorted(DEF_SCHEME_MAP),
        "note": "the vocabulary of offSchemeGuess/defSchemeGuess, kept for traceability",
    }
    doc["schemeMapping"] = {"off": OFF_SCHEME_MAP, "def": DEF_SCHEME_MAP,
                            "overrides": overrides}
    doc["abbrNormalization"] = renamed
    doc["teamAbbrConvention"] = "nflverse (LA = Rams, LAC = Chargers)"

    with open(path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    return doc, off_hist, def_hist, renamed, overrides


# --------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------
def main():
    print("loading local sources ...")
    players = load_players()
    jerseys_by_team, jerseys_any = load_jerseys()
    anchor_week, last_game_type, active, reserve = load_rosters()
    snaps, snap_last_game = load_snaps()
    last_game = load_last_game_dates(snap_last_game)
    base_def, anchor_dc, latest_dc, anchor_dt, ever_rank1, window_dc = load_depth_charts(last_game)
    pfr_roster = load_pfr_rosters()
    adv_gs = load_advstats_gs()
    draft_by_gsis, draft_by_namecoll = load_draft()
    reg_stats, regpost_stats = load_stats()

    staffs_doc, off_hist, def_hist, staff_renamed, staff_overrides = normalise_staffs(base_def)

    dp2026_path = os.path.join(RAW, "draft_picks_2026.json")
    with open(need(dp2026_path), encoding="utf-8") as fh:
        dp2026 = json.load(fh)
    records = dp2026.get("records2025") or {}
    order = dp2026.get("draftOrder2026") or []
    sb_champ = order[-1] if len(order) == 32 else None
    sb_loser = order[-2] if len(order) == 32 else None
    if not records:
        sys.exit("FATAL: draft_picks_2026.json has no records2025")

    print("  per-team anchors (final game date / depth-chart snapshot / roster week):")
    for t in sorted(TEAM_NAMES):
        print(f"    {t:<4} {last_game[t]}  {anchor_dt[t][:10]}  wk{anchor_week[t]}  {base_def[t]}")

    tot = Counter()
    holes = []
    all_violations = {}
    team_summary = {}
    team_docs = {}
    reconciled = []
    depth_flips = []          # season-primacy disagreed with the week-21 depth chart
    jersey_collisions = []    # two players sharing a number (real: IR number re-issues)

    for team in sorted(TEAM_NAMES):
        bd = base_def[team]
        quota = starter_quota(bd)
        r1days = rank1_days(team, bd, window_dc)

        state = {"t": 0, "g": 0, "s": 0}

        def tackle_alt():
            state["t"] += 1
            return "RT" if state["t"] % 2 == 1 else "LT"

        def guard_alt():
            state["g"] += 1
            return "RG" if state["g"] % 2 == 1 else "LG"

        def safety_alt():
            state["s"] += 1
            return "FS" if state["s"] % 2 == 1 else "SS"

        # ---- assemble candidate roster: active (ACT/INA) + notable IR (RES) ----
        cand = [(r, False) for r in sorted(active[team], key=lambda x: x["gsis_id"])]

        ir_pool = []
        for r in sorted(reserve[team], key=lambda x: x["gsis_id"]):
            pfr = r["pfr_id"] or players.get(r["gsis_id"], {}).get("pfr_id", "")
            s = snaps.get((pfr, 2025), {}).get("reg") if pfr else None
            total = (s["off"] + s["def"]) if s else 0
            notable = total >= 100 or r["gsis_id"] in ever_rank1[team]
            if notable and r["position"] != "LS":
                ir_pool.append((total, r))
        ir_pool.sort(key=lambda x: (-x[0], x[1]["gsis_id"]))
        for _, r in ir_pool[:MAX_IR]:
            cand.append((r, True))

        built = []
        for rw, is_ir in cand:
            gid = rw["gsis_id"]
            pl = players.get(gid, {})

            pos, psrc = resolve_position(rw, team, bd, latest_dc, anchor_dc,
                                         tackle_alt, guard_alt, safety_alt)
            if pos is None:
                if psrc == "unresolved":
                    holes.append((team, rw["full_name"], rw["position"], "position unresolved"))
                    tot["pos_unresolved"] += 1
                continue
            if pos not in GAME_POSITIONS:
                holes.append((team, rw["full_name"], pos, "position outside schema vocabulary"))
                tot["pos_unresolved"] += 1
                continue
            if psrc == "fallback":
                tot["pos_fallback"] += 1

            name = rw["full_name"] or pl.get("display_name") or ""
            birth = rw["birth_date"] or pl.get("birth_date", "")
            age = age_on(birth, AGE_AS_OF)
            if age is None:
                tot["null_age"] += 1
                holes.append((team, name, pos, "no birth date"))
            college = (rw["college"] or pl.get("college_name") or "").strip() or None
            if college is None:
                tot["null_college"] += 1
                holes.append((team, name, pos, "no college"))
            hin = i(rw["height"]) or i(pl.get("height"))
            wlb = i(rw["weight"]) or i(pl.get("weight"))
            if hin is None:
                tot["null_height"] += 1
                holes.append((team, name, pos, "no height"))
            if wlb is None:
                tot["null_weight"] += 1
                holes.append((team, name, pos, "no weight"))
            entry = i(rw["entry_year"]) or i(rw["rookie_year"]) or i(pl.get("rookie_season"))
            years_pro = (2026 - entry) if entry else None
            if years_pro is None:
                tot["null_yearspro"] += 1
                holes.append((team, name, pos, "no entry year"))

            jersey = jerseys_by_team.get((gid, team))
            if jersey is None:
                jersey = i(rw.get("jersey_number"))
            if jersey is None:
                jersey = jerseys_any.get(gid)
            if jersey is None:
                tot["null_jersey"] += 1
                holes.append((team, name, pos, "no jersey number"))

            notes = []
            d = draft_by_gsis.get(gid)
            if d is None:
                key = (name.strip().lower(), (college or "").strip().lower())
                d = draft_by_namecoll.get(key)
                if d is not None:
                    tot["draft_by_name"] += 1
            if d is None:
                tot["null_draft"] += 1
                notes.append("No entry in nflverse draft_picks (1980-2026); treated as undrafted.")
            draft = dict(d) if d else None

            pfr = rw["pfr_id"] or pl.get("pfr_id", "")
            if not pfr:
                tot["null_pfr_id"] += 1
                holes.append((team, name, pos, "no pfr_id -> no snap counts"))
            s25 = snaps.get((pfr, 2025), {}).get("reg") if pfr else None
            side_snaps = 0
            if s25:
                if pos in OFFENSE_POS:
                    side_snaps = s25["off"]
                elif pos in DEFENSE_POS:
                    side_snaps = s25["def"]
                else:
                    side_snaps = s25["st"]
            share25 = snap_share(s25) if s25 else None
            vol = volume_for(pos, reg_stats.get(gid, {}).get(2025))

            built.append({
                "_gid": gid, "_pfr": pfr, "_pos": pos, "_ir": is_ir,
                "_share": share25 or 0.0,
                "_side": side_snaps,
                "_vol": vol,
                "_r1": r1days.get(gid, 0),
                "_st": s25["st"] if s25 else 0,
                "_games25": s25["games"] if s25 else 0,
                "_notes": notes,
                "_ir_week": anchor_week[team] if is_ir else None,
                "rec": {
                    "name": name,
                    "pos": pos,
                    "jersey": jersey,
                    "age": age,
                    "yearsPro": years_pro,
                    "college": college,
                    "draft": draft,
                    "heightIn": hin,
                    "weightLb": wlb,
                    "role": None,
                    "depthChartRank": None,
                    "injuredAtSeasonEnd": bool(is_ir),
                    "seasons": [],
                    "notes": None,
                },
            })

        # ------------------------------------------------------------------
        # DEPTH ORDER (QA_REPORT M2): rank inside team+position by season-long
        # 2025 primacy, NOT by the week-21 depth-chart photograph.
        # ------------------------------------------------------------------
        by_pos = defaultdict(list)
        for b in built:
            by_pos[b["_pos"]].append(b)

        # fill an empty base-lineup slot from the mirrored position's surplus
        for pos, want in sorted(quota.items()):
            if want < 1 or by_pos.get(pos):
                continue
            for sib in POSITION_SIBLINGS.get(pos, []):
                pool = by_pos.get(sib, [])
                if len(pool) <= quota.get(sib, 0):
                    continue
                pool.sort(key=lambda b: (-b["_side"], -b["_vol"], -b["_r1"], b["_gid"]))
                mover = pool[-1]
                pool.remove(mover)
                mover["_pos"] = pos
                mover["rec"]["pos"] = pos
                mover["_notes"].append(
                    f"Listed at {sib} on the 2025 depth chart; reassigned to {pos} to fill an "
                    f"otherwise empty base-lineup slot.")
                by_pos[pos].append(mover)
                reconciled.append((team, f"{sib}->{pos} to fill empty slot", 1))
                tot["pos_reassigned"] += 1
                break

        for pos, group in by_pos.items():
            group.sort(key=lambda b: (-b["_side"], -b["_vol"], -b["_r1"], b["_gid"]))
            want = quota.get(pos, 0)
            for idx, b in enumerate(group, start=1):
                b["rec"]["depthChartRank"] = idx
                if idx <= want:
                    b["rec"]["role"] = "starter"
                elif b["_share"] >= ROTATION_SNAP_SHARE:
                    b["rec"]["role"] = "rotation"
                elif b["_side"] > 0 or b["_st"] > 0 or b["_games25"] > 0:
                    b["rec"]["role"] = "backup"
                else:
                    b["rec"]["role"] = "depth"
            # record where season primacy overruled the closing depth chart
            for b in group[:want]:
                if b["_ir"]:
                    depth_flips.append((team, pos, b["rec"]["name"], "IR at season end, "
                                        "season totals still rank him first"))
            for b in group[want:]:
                if b["_r1"] > 0 and want:
                    tot["demoted_by_primacy"] += 1

        # ---- seasons ----
        for b in built:
            pos = b["_pos"]
            gid = b["_gid"]
            pfr = b["_pfr"]
            per_reg = reg_stats.get(gid, {})
            per_rp = regpost_stats.get(gid, {})

            # every season in which he demonstrably appeared
            years = set()
            for y in CAREER_YEARS:
                if y in per_reg or y in per_rp:
                    years.add(y)
                    continue
                if pfr:
                    sn = snaps.get((pfr, y))
                    if sn and (sn["reg"]["games"] or sn["post"]["games"]):
                        years.add(y)
                        continue
                    pr = pfr_roster.get((pfr, y))
                    if pr and (pr["g"] or 0) > 0:
                        years.add(y)
            pick = sorted(years)[-MAX_CAREER_SEASONS:]

            seasons = []
            for y in pick:
                rg = per_reg.get(y)
                rp = per_rp.get(y)
                sn = snaps.get((pfr, y)) if pfr else None
                sn_reg = sn["reg"] if sn else None
                sn_post = sn["post"] if sn else None
                pr = pfr_roster.get((pfr, y)) if pfr else None

                # ---- games played (regular season) ----
                gp = None
                if pr and pr["g"] is not None and y <= PFR_ROSTER_MAX_YEAR:
                    gp = pr["g"]
                elif sn_reg and sn_reg["games"]:
                    gp = sn_reg["games"]
                elif rg is not None and pos not in OL_POS:
                    gp = i(rg.get("games"), 0)
                if gp is None:
                    tot["gp_null"] += 1

                if gp is not None and gp > season_games(y):
                    gp = season_games(y)

                # ---- games started (regular season) ----
                gs, gs_src = None, None
                if pr and pr["gs"] is not None and y <= PFR_ROSTER_MAX_YEAR:
                    gs, gs_src = pr["gs"], "pfrRoster"
                elif pfr and (pfr, y) in adv_gs:
                    gs, gs_src = adv_gs[(pfr, y)], "pfrAdvStats"
                elif pos in OL_POS and sn_reg and sn_reg["off_g"]:
                    gs, gs_src = sn_reg["start50"], "snapStart50"
                elif pos in ST_POS and gp is not None:
                    gs, gs_src = 0, "pfrConventionKP"
                if gs is None:
                    tot["gs_null"] += 1
                else:
                    tot["gs_" + gs_src] += 1
                    if gs > season_games(y):
                        gs = season_games(y)
                    if gp is not None and gs > gp:
                        gs = gp   # cannot start more games than you played

                share = snap_share(sn_reg) if sn_reg else None
                ol_snaps = sn_reg["off"] if (pos in OL_POS and sn_reg) else None

                row = {
                    "year": y,
                    "team": (rg or rp or {}).get("recent_team") or (team if y == 2025 else None),
                    "gp": gp,
                    "gs": gs,
                    "gsSrc": gs_src,
                    "snapShare": share,
                    "stats": project_stats(pos, rg, ol_snaps=ol_snaps)
                    if (rg is not None or pos in OL_POS) else zero_stats(pos),
                }
                if row["stats"]:
                    tot["stats_nonempty"] += 1

                po = post_row(rp, rg)
                if po is not None:
                    p_gp = None
                    if sn_post and sn_post["games"]:
                        p_gp = sn_post["games"]
                    elif pos not in OL_POS:
                        p_gp = i(po.get("games"), 0) or None
                    p_snaps = sn_post["off"] if (pos in OL_POS and sn_post) else None
                    row["post"] = {
                        "gp": p_gp,
                        "snapShare": snap_share(sn_post) if sn_post else None,
                        "stats": project_stats(pos, po, ol_snaps=p_snaps),
                    }
                    tot["post_rows"] += 1

                seasons.append(row)

            b["rec"]["seasons"] = seasons
            tot["season_rows"] += len(seasons)
            if not seasons:
                tot["null_seasons"] += 1
                holes.append((team, b["rec"]["name"], pos, "no career stats, snaps or PFR rows"))

            notes = list(b["_notes"])
            if b["_ir"]:
                notes.insert(0, f"On reserve/injured (roster status RES) at the team's final "
                                f"2025 game week {b['_ir_week']}.")
            b["rec"]["notes"] = " ".join(notes) if notes else None

        players_out = [b["rec"] for b in built]
        players_out.sort(key=lambda p: (
            ["starter", "rotation", "backup", "depth"].index(p["role"]),
            p["pos"], p["depthChartRank"], p["name"]))

        # ---- record2025 ----
        rec = records.get(team)
        gt = last_game_type.get(team, "REG")
        made = gt != "REG"
        if gt == "WC":
            result = "Lost Wild Card round"
        elif gt == "DIV":
            result = "Lost Divisional round"
        elif gt == "CON":
            result = "Lost Conference Championship"
        elif gt == "SB":
            if team == sb_champ:
                result = "Won Super Bowl LX"
            elif team == sb_loser:
                result = "Lost Super Bowl LX"
            else:
                result = "Reached Super Bowl LX"
        else:
            result = None
        if rec is None:
            tot["null_record"] += 1
            record2025 = {"wins": None, "losses": None, "ties": None,
                          "madePlayoffs": made, "playoffResult": result}
        else:
            record2025 = {"wins": rec["wins"], "losses": rec["losses"],
                          "ties": rec.get("ties", 0), "madePlayoffs": made,
                          "playoffResult": result}

        # ---- gates ----
        pc = Counter(p["pos"] for p in players_out)
        sc = Counter(p["pos"] for p in players_out if p["role"] == "starter")
        n_ol = sum(pc[x] for x in OL_POS)
        n_db = sum(pc[x] for x in DB_POS)
        n_start = sum(1 for p in players_out if p["role"] == "starter")
        off_start = sum(sc[x] for x in OFFENSE_POS)
        def_start = sum(sc[x] for x in DEFENSE_POS)
        st_start = sum(sc[x] for x in ST_POS)
        v = []
        if not (MIN_ROSTER <= len(players_out) <= MAX_ROSTER):
            v.append(f"roster size {len(players_out)} outside [{MIN_ROSTER},{MAX_ROSTER}]")
        if pc["QB"] < 2:
            v.append(f"QB count {pc['QB']} < 2")
        if n_ol < 8:
            v.append(f"OL count {n_ol} < 8")
        if pc["K"] < 1:
            v.append("K count 0 < 1")
        if pc["P"] < 1:
            v.append("P count 0 < 1")
        if n_db < 8:
            v.append(f"DB count {n_db} < 8")
        if not (MIN_STARTERS <= n_start <= MAX_STARTERS):
            v.append(f"starters {n_start} outside [{MIN_STARTERS},{MAX_STARTERS}]")
        # v2 gates -- QA_REPORT M3
        if off_start != 11:
            v.append(f"offensive starters {off_start} != 11 ({dict(sorted((k, sc[k]) for k in OFFENSE_POS if sc[k]))})")
        if def_start != 11:
            v.append(f"defensive starters {def_start} != 11 ({dict(sorted((k, sc[k]) for k in DEFENSE_POS if sc[k]))})")
        if st_start != 2:
            v.append(f"special-teams starters {st_start} != 2")
        for p_, q_ in sorted(quota.items()):
            if sc[p_] > q_:
                v.append(f"{sc[p_]} starting {p_} > quota {q_}")
        dupe_rank = [p_ for p_ in pc
                     if len({q["depthChartRank"] for q in players_out if q["pos"] == p_}) != pc[p_]]
        if dupe_rank:
            v.append(f"duplicate depthChartRank at {sorted(dupe_rank)}")
        bad_games = [f"{p_['name']} {s_['year']} gp={s_['gp']} gs={s_['gs']}"
                     for p_ in players_out for s_ in p_["seasons"]
                     if (s_["gp"] is not None and s_["gp"] > season_games(s_["year"]))
                     or (s_["gs"] is not None and s_["gs"] > season_games(s_["year"]))
                     or (s_["gs"] is not None and s_["gp"] is not None and s_["gs"] > s_["gp"])]
        if bad_games:
            v.append(f"{len(bad_games)} impossible gp/gs rows e.g. {bad_games[:3]}")

        jc = Counter(p_["jersey"] for p_ in players_out if p_["jersey"] is not None)
        for num, cnt in sorted(jc.items()):
            if cnt > 1:
                who = [f"{p_['name']} ({p_['pos']}, "
                       f"{'IR' if p_['injuredAtSeasonEnd'] else 'active'})"
                       for p_ in players_out if p_["jersey"] == num]
                jersey_collisions.append((team, num, who))
        if v:
            all_violations[team] = v
            for msg in v:
                print(f"  QA VIOLATION {team}: {msg}")

        conf, div = CONF_DIV[team]
        out = {
            "team": TEAM_NAMES[team],
            "abbr": team,
            "conference": conf,
            "division": div,
            "baseDefense": bd,
            "record2025": record2025,
            "schemaNotes": SCHEMA_NOTES,
            "players": players_out,
            "sources": SOURCES,
        }
        if v:
            out["_qaViolations"] = v

        path = os.path.join(RAW, f"{team}.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(out, fh, indent=1, ensure_ascii=False)
            fh.write("\n")
        team_docs[team] = out

        # completeness, per team
        srows = [s for p in players_out for s in p["seasons"]]
        ol_rows = [s for p in players_out if p["pos"] in OL_POS for s in p["seasons"]]
        exp = sum(min(p["yearsPro"] or 0, MAX_CAREER_SEASONS) for p in players_out)
        team_summary[team] = {
            "players": len(players_out),
            "starters": n_start,
            "offStarters": off_start,
            "defStarters": def_start,
            "rotation": sum(1 for p in players_out if p["role"] == "rotation"),
            "backup": sum(1 for p in players_out if p["role"] == "backup"),
            "depth": sum(1 for p in players_out if p["role"] == "depth"),
            "injured": sum(1 for p in players_out if p["injuredAtSeasonEnd"]),
            "QB": pc["QB"], "RB": pc["RB"], "FB": pc["FB"], "WR": pc["WR"], "TE": pc["TE"],
            "OL": n_ol, "DE": pc["DE"], "DT": pc["DT"], "OLB": pc["OLB"], "MLB": pc["MLB"],
            "DB": n_db, "K": pc["K"], "P": pc["P"],
            "baseDef": bd,
            "anchorWeek": anchor_week[team],
            "conference": conf, "division": div,
            "offScheme": staffs_doc["staffs"][team]["offScheme"],
            "defScheme": staffs_doc["staffs"][team]["defScheme"],
            "seasonRows": len(srows),
            "seasonRowsExpected": exp,
            "gsFilled": sum(1 for s in srows if s["gs"] is not None),
            "gpFilled": sum(1 for s in srows if s["gp"] is not None),
            "olRows": len(ol_rows),
            "olRowsWithStats": sum(1 for s in ol_rows if s["gp"] is not None or s["gs"] is not None),
            "olRowsWithGpAndGs": sum(1 for s in ol_rows if s["gp"] is not None and s["gs"] is not None),
            "postRows": sum(1 for s in srows if "post" in s),
        }
        tot["players"] += len(players_out)
        tot["expected_rows"] += exp

    # ------------------------------------------------------------------
    # Merged artifact
    # ------------------------------------------------------------------
    generated = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    merged = {
        "schemaVersion": 2,
        "generated": generated,
        "compiledNote": ("Raw real-name NFL data. Never ship without anonymization "
                         "(docs/ANONYMIZATION_SPEC.md 6.5): this file lives only in "
                         "tools/league-data/raw/ and must never enter a target's resources."),
        "compiledBy": "tools/league-data/build_raw.py v2",
        "teamAbbrConvention": "nflverse (LA = Rams, LAC = Chargers)",
        "schemaNotes": SCHEMA_NOTES,
        "divisions": {f"{c} {d}": t for (c, d), t in sorted(DIVISIONS.items())},
        "teams": [team_docs[t] for t in sorted(TEAM_NAMES)],
        "draft": dp2026,
        "staffs": staffs_doc,
    }

    n = tot["players"]
    rows = tot["season_rows"]
    exp_rows = tot["expected_rows"]
    gs_filled = rows - tot["gs_null"]
    ol_rows = sum(s["olRows"] for s in team_summary.values())
    ol_ok = sum(s["olRowsWithStats"] for s in team_summary.values())
    ol_both = sum(s["olRowsWithGpAndGs"] for s in team_summary.values())

    merged["qa"] = {
        "teamCount": len(team_docs),
        "playerCount": n,
        "seasonRowCount": rows,
        "seasonRowsExpected": exp_rows,
        "careerCoveragePct": round(100.0 * rows / exp_rows, 2) if exp_rows else None,
        "gsFilledPct": round(100.0 * gs_filled / rows, 2) if rows else None,
        "gsSources": {k[3:]: tot[k] for k in sorted(tot) if k.startswith("gs_") and k != "gs_null"},
        "gpFilledPct": round(100.0 * (rows - tot["gp_null"]) / rows, 2) if rows else None,
        # NOTE: olRowsWithGamesPct is an OR (gp or gs present). The stricter AND -- what a
        # starts-based model actually needs -- is olRowsWithGpAndGsPct. Keep both; the OR
        # alone overstates OL coverage by ~2 points.
        "olRowsWithGamesPct": round(100.0 * ol_ok / ol_rows, 2) if ol_rows else None,
        "olRowsWithGpAndGsPct": round(100.0 * ol_both / ol_rows, 2) if ol_rows else None,
        "postseasonSubObjects": tot["post_rows"],
        "violations": all_violations,
        "abbrNormalization": staff_renamed,
        "schemeOverrides": staff_overrides,
        "resolvedBlockers": [
            "B1 coaching_staffs_2026.json re-keyed LAR->LA",
            "B2 offScheme/defScheme emitted in the Swift enum vocabulary (32/32 decodable)",
            "B3 WideZone re-graded where the notes disagree (see schemeMapping.overrides)",
            "B4 conference + division on every team file",
            "M1 gs populated from PFR roster + advanced season tables",
            "M2 role is now the depth order entering 2026 (+ depthChartRank, injuredAtSeasonEnd)",
            "M3 offensive/defensive starter counts are gated at 11/11",
            "M4 int/td split into defInt/defTd on defensive rows",
            "m1 season rows are REG only; postseason moved to seasons[].post",
        ],
        "independentAudit": QA_V2_AUDIT,
        "depthOrderSuspects": depth_order_suspects(),
    }
    with open(os.path.join(RAW, "league_raw_2026.json"), "w", encoding="utf-8") as fh:
        json.dump(merged, fh, indent=1, ensure_ascii=False)
        fh.write("\n")

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    print("\n=== PER-TEAM ===")
    print(f"{'tm':>4} {'cf':>4} {'div':>6} {'n':>4} {'st':>3} {'off':>4} {'def':>4} "
          f"{'rot':>4} {'bkp':>4} {'dep':>4} {'inj':>4} {'QB':>3} {'RB':>3} {'FB':>3} "
          f"{'WR':>3} {'TE':>3} {'OL':>3} {'DE':>3} {'DT':>3} {'OLB':>4} {'MLB':>4} "
          f"{'DB':>3} {'K':>2} {'P':>2} {'base':>5} {'rows':>5} {'exp':>5} {'cov%':>6} "
          f"{'gs%':>6} {'OLgp%':>6}  {'offScheme':<11} {'defScheme'}")
    for t, s in sorted(team_summary.items()):
        cov = 100.0 * s["seasonRows"] / s["seasonRowsExpected"] if s["seasonRowsExpected"] else 0
        gsp = 100.0 * s["gsFilled"] / s["seasonRows"] if s["seasonRows"] else 0
        olp = 100.0 * s["olRowsWithStats"] / s["olRows"] if s["olRows"] else 0
        print(f"{t:>4} {s['conference']:>4} {s['division']:>6} {s['players']:>4} "
              f"{s['starters']:>3} {s['offStarters']:>4} {s['defStarters']:>4} "
              f"{s['rotation']:>4} {s['backup']:>4} {s['depth']:>4} {s['injured']:>4} "
              f"{s['QB']:>3} {s['RB']:>3} {s['FB']:>3} {s['WR']:>3} {s['TE']:>3} {s['OL']:>3} "
              f"{s['DE']:>3} {s['DT']:>3} {s['OLB']:>4} {s['MLB']:>4} {s['DB']:>3} "
              f"{s['K']:>2} {s['P']:>2} {s['baseDef'][5:8]:>5} {s['seasonRows']:>5} "
              f"{s['seasonRowsExpected']:>5} {cov:>6.1f} {gsp:>6.1f} {olp:>6.1f}  "
              f"{s['offScheme']:<11} {s['defScheme']}")

    print("\n=== COMPLETENESS ===")
    print(f"  players                          {n}")
    print(f"  season rows (REG)                {rows}   (v1: 5367)")
    print(f"  expected rows sum(min(yrsPro,8)) {exp_rows}")
    print(f"  career coverage                  {100.0*rows/exp_rows:6.2f}%   (v1: 67.90%)")
    print(f"  gs (games started) populated     {100.0*gs_filled/rows:6.2f}%   (v1:  0.00%)   "
          f"{gs_filled}/{rows}")
    for k in sorted(k for k in tot if k.startswith("gs_") and k != "gs_null"):
        print(f"      via {k[3:]:<14} {tot[k]:>6}")
    print(f"      still null            {tot['gs_null']:>6}")
    print(f"  gp (games played) populated      {100.0*(rows-tot['gp_null'])/rows:6.2f}%   (v1: 88.71%)")
    print(f"  OL season rows with gp or gs     {100.0*ol_ok/ol_rows:6.2f}%   (v1:  0.00%)   "
          f"{ol_ok}/{ol_rows}")
    print(f"  season rows with non-empty stats {100.0*tot['stats_nonempty']/rows:6.2f}%   (v1: 83.30%)")
    print(f"  postseason sub-objects           {tot['post_rows']}")
    print(f"  jersey numbers populated         {100.0*(n-tot['null_jersey'])/n:6.2f}%   (v1:  0.00%)")

    print("\n=== NULL RATES (of %d players) ===" % n)
    for k, label in [("null_draft", "draft info null (undrafted / no draft row)"),
                     ("null_seasons", "no season rows at all"),
                     ("null_age", "age null"),
                     ("null_college", "college null"),
                     ("null_height", "heightIn null"),
                     ("null_weight", "weightLb null"),
                     ("null_yearspro", "yearsPro null"),
                     ("null_jersey", "jersey null"),
                     ("null_pfr_id", "no pfr_id (snap counts unavailable)"),
                     ("pos_fallback", "position from roster fallback (no depth chart)"),
                     ("pos_reassigned", "position reassigned to fill an empty lineup slot"),
                     ("pos_unresolved", "player dropped, position unresolvable")]:
        c = tot[k]
        print(f"  {label:<48} {c:>5}  ({100.0*c/n:5.2f}%)")
    print(f"  draft matched via name+college fallback: {tot['draft_by_name']}")
    print(f"  record2025 missing: {tot['null_record']}")

    print("\n=== SCHEME DISTRIBUTION (Swift enum raw values) ===")
    print("  off: " + ", ".join(f"{k}={v}" for k, v in off_hist.most_common()))
    print("  def: " + ", ".join(f"{k}={v}" for k, v in def_hist.most_common()))
    if staff_overrides:
        print("  overrides: " + "; ".join(staff_overrides))

    print("\n=== VIOLATIONS ===")
    if all_violations:
        for t, v in sorted(all_violations.items()):
            print(f"  {t}: {'; '.join(v)}")
    else:
        print("  none")

    print("\n=== DEPTH-ORDER FLIPS (season primacy beat the week-21 chart) ===")
    if depth_flips:
        for t, pos, nm, why in depth_flips:
            print(f"  {t} {pos:<4} {nm}: {why}")
    else:
        print("  none")
    print(f"  players who held a rank-1 slot late but rank below the quota line: "
          f"{tot['demoted_by_primacy']}")

    print("\n=== JERSEY COLLISIONS (real: a number re-issued after an IR placement) ===")
    if jersey_collisions:
        for t, num, who in jersey_collisions:
            print(f"  {t} #{num}: {' / '.join(who)}")
    else:
        print("  none")

    print("\n=== LINEUP REPAIRS ===")
    if reconciled:
        for t, how, k in reconciled:
            print(f"  {t}: {how} ({k})")
    else:
        print("  none")

    print("\n=== WORST DATA HOLES ===")
    byk = Counter(h[3] for h in holes)
    for k, c in byk.most_common(12):
        ex = [f"{h[0]} {h[1]} ({h[2]})" for h in holes if h[3] == k][:4]
        print(f"  {c:>4}x {k}  e.g. {', '.join(ex)}")

    with open(os.path.join(RAW, "_build_summary.json"), "w", encoding="utf-8") as fh:
        json.dump({
            "generatedBy": "tools/league-data/build_raw.py v2",
            "generated": generated,
            "schemaVersion": 2,
            "completeness": merged["qa"],
            "perTeam": team_summary,
            "nullCounts": dict(tot),
            "violations": all_violations,
            "lineupRepairs": [{"team": t, "action": h, "count": k} for t, h, k in reconciled],
            "jerseyCollisions": [{"team": t, "jersey": num, "players": who}
                                 for t, num, who in jersey_collisions],
            "depthOrderFlips": [{"team": t, "pos": p, "player": nm, "why": w}
                                for t, p, nm, w in depth_flips],
            "schemeDistribution": {"off": dict(off_hist), "def": dict(def_hist),
                                   "overrides": staff_overrides},
            "anchors": {t: {"lastGame": last_game[t], "depthChart": anchor_dt[t],
                            "rosterWeek": anchor_week[t], "baseDefense": base_def[t],
                            "conference": CONF_DIV[t][0], "division": CONF_DIV[t][1]}
                        for t in sorted(TEAM_NAMES)},
            "dataHoles": [{"team": a, "player": b, "pos": c, "issue": d} for a, b, c, d in holes],
        }, fh, indent=1)

    print(f"\nwrote {len(team_summary)} team files + coaching_staffs_2026.json "
          f"+ league_raw_2026.json + _build_summary.json to {RAW}")
    return 1 if all_violations else 0


if __name__ == "__main__":
    sys.exit(main())
