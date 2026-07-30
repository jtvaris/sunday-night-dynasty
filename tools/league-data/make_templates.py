#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_templates.py — Phase-3 league-template transform.

Reads the repo-internal, real-name snapshot
    tools/league-data/raw/league_raw_2026.json
and bakes TWO complete, constant, always-launchable league templates:

    out/league_2026_dev.json      devProfile     (DEBUG builds only)
    out/league_2026_publish.json  publishProfile (bundled in every build)

Everything is deterministic: every random draw is seeded from
SHA-256(GLOBAL_SEED | stable per-entity key), so re-running the tool byte-for-byte
reproduces both files. Nothing is generated at career-creation time — the
templates already carry the final rating targets, potentials and career arcs.

Reference documents (binding):
    docs/REALISTIC_LEAGUE_PLAN.md   pipeline + two-template requirement
    docs/ANONYMIZATION_SPEC.md      legal rules for publishProfile
    tools/league-data/raw/QA_REPORT.md   data state + 5 carry-in conditions

CALIBRATION DECISION (binding, 2026-07-29)
------------------------------------------
The template league must sit at the SAME level and spread as the existing random
`LeagueGenerator` output — league mean OVR ~= 76.4 with its starter / backup /
depth tier structure — so every balance threshold in the engine behaves
identically no matter which of the three league sources the player picked.
This is deliberately NOT the DEVELOPMENT_NFL_REFERENCE.md section-8 absolute
band exercise; that is a separate, deferred wave.

Team-to-team spread follows real 2025 strength, with the best teams about
+4..6 OVR over the worst (see `TEAM_SPREAD_TARGET`).

Usage:  python3 tools/league-data/make_templates.py [--out DIR] [--quiet]
Exit code 0 only if every QA gate passes.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import math
import os
import random
import re
import statistics
import sys
from collections import defaultdict, deque

# ---------------------------------------------------------------------------
# 0. Constants / configuration
# ---------------------------------------------------------------------------

GLOBAL_SEED = 20260729          # bump ONLY when a full regeneration is intended
SCHEMA_VERSION = 1
SNAPSHOT_YEAR = 2025            # last completed season in the raw data
LEAGUE_YEAR = 2026              # the season the template starts

HERE = os.path.dirname(os.path.abspath(__file__))
RAW_PATH = os.path.join(HERE, "raw", "league_raw_2026.json")
DEFAULT_OUT = os.path.join(HERE, "out")

NO_COLLEGE = "No College"       # QA_REPORT carry-in #3: sentinel, never null

# --- calibration bands (QA gates fail the run outside these) ---------------
CALIB_MEAN_BAND = (75.4, 77.4)      # league mean OVR; reference generator = 76.46
CALIB_SD_BAND = (7.0, 9.4)          # league OVR sd;   reference generator = 8.23
TEAM_SPREAD_TARGET = 5.0            # best team mean minus worst team mean
TEAM_SPREAD_BAND = (4.0, 6.0)
TEAM_STRENGTH_CORR_MIN = 0.55       # Spearman(team mean OVR, 2025 wins)
REF_SIM_REPS = 140                  # reference-distribution Monte-Carlo reps

# Elite tail: the reference generator tops out around 94. Genuine, decorated
# stars are allowed a small stretch into 90-96 (task brief); the stretch touches
# only the top ~1.2 % of the league so the mean moves by < 0.05.
ELITE_STRETCH_PCTL = 0.988
ELITE_STRETCH_MAX = 3.0

# ---------------------------------------------------------------------------
# 1. Seeded-RNG plumbing
# ---------------------------------------------------------------------------


def seeded(*parts) -> random.Random:
    """A `random.Random` keyed by GLOBAL_SEED + a stable entity key."""
    key = "|".join(str(p) for p in (GLOBAL_SEED,) + parts)
    digest = hashlib.sha256(key.encode("utf-8")).digest()
    return random.Random(int.from_bytes(digest[:16], "big"))


def stable_id(*parts) -> str:
    key = "|".join(str(p) for p in (GLOBAL_SEED,) + parts)
    return hashlib.sha256(key.encode("utf-8")).hexdigest()[:16]


# ---------------------------------------------------------------------------
# 2. Mirror of the Swift generator's rating math
#    (dynasty/Domain/Models/Player/PositionPhysicalProfile.swift,
#     dynasty/Data/Import/LeagueGenerator.swift)
#    Used ONLY to build the reference OVR distribution we calibrate onto.
# ---------------------------------------------------------------------------

POSITIONS = ["QB", "RB", "FB", "WR", "TE", "LT", "LG", "C", "RG", "RT",
             "DE", "DT", "OLB", "MLB", "CB", "FS", "SS", "K", "P"]

PEAK_AGE = {
    "QB": (28, 35), "RB": (24, 28), "FB": (24, 28), "WR": (26, 31), "TE": (26, 31),
    "LT": (26, 32), "LG": (26, 32), "C": (26, 32), "RG": (26, 32), "RT": (26, 32),
    "DE": (26, 31), "DT": (26, 31), "OLB": (25, 30), "MLB": (25, 30), "CB": (25, 30),
    "FS": (26, 31), "SS": (26, 31), "K": (28, 38), "P": (28, 38),
}

# LeagueGenerator.careerAgeSpan — the generator draws `min(U, U)` from this
# span, which is what makes its age pyramid (and therefore its rating level)
# what it is. The reference pools below sample ages the same way, so the
# template is calibrated against the generator's OWN league, not against a
# hybrid of the generator's ratings and real NFL ages.
CAREER_AGE_SPAN = {
    "QB": (22, 38), "RB": (21, 31), "FB": (21, 31), "WR": (21, 34), "TE": (22, 33),
    "LT": (22, 35), "LG": (22, 35), "C": (22, 35), "RG": (22, 35), "RT": (22, 35),
    "DE": (22, 34), "DT": (22, 34), "OLB": (22, 33), "MLB": (22, 33), "CB": (21, 33),
    "FS": (22, 33), "SS": (22, 33), "K": (22, 40), "P": (22, 40),
}

# LeagueGenerator.rosterBlueprint — the 53-man shape whose league mean OVR
# (~76.46) is the binding calibration anchor.
ROSTER_BLUEPRINT = [("QB", 3), ("RB", 3), ("FB", 1), ("WR", 7), ("TE", 3),
                    ("LT", 2), ("LG", 2), ("C", 2), ("RG", 2), ("RT", 1),
                    ("DE", 5), ("DT", 3), ("OLB", 4), ("MLB", 3),
                    ("CB", 6), ("FS", 2), ("SS", 2), ("K", 1), ("P", 1)]

_STAM = (70.0, 8.0)
_DUR = (72.0, 9.0)
PHYS_PRIORS = {
    "QB":  [(62, 8), (68, 7), (55, 8), (68, 7)],
    "RB":  [(82, 5), (84, 5), (66, 7), (82, 5)],
    "FB":  [(62, 6), (66, 6), (76, 6), (60, 6)],
    "WR":  [(85, 5), (86, 5), (52, 7), (84, 5)],
    "TE":  [(70, 6), (72, 6), (72, 6), (66, 6)],
    "LT":  [(47, 6), (52, 6), (84, 5), (54, 6)],
    "RT":  [(47, 6), (52, 6), (84, 5), (54, 6)],
    "LG":  [(45, 6), (50, 6), (86, 5), (52, 6)],
    "C":   [(45, 6), (50, 6), (86, 5), (52, 6)],
    "RG":  [(45, 6), (50, 6), (86, 5), (52, 6)],
    "DE":  [(73, 6), (76, 6), (78, 6), (72, 6)],
    "DT":  [(55, 7), (62, 7), (87, 5), (58, 7)],
    "OLB": [(76, 5), (78, 5), (74, 6), (74, 5)],
    "MLB": [(73, 5), (75, 5), (75, 6), (71, 5)],
    "CB":  [(86, 4), (87, 4), (48, 7), (85, 4)],
    "FS":  [(82, 5), (83, 5), (58, 7), (80, 5)],
    "SS":  [(82, 5), (83, 5), (58, 7), (80, 5)],
    "K":   [(50, 8), (52, 8), (45, 8), (55, 8)],
    "P":   [(50, 8), (52, 8), (45, 8), (55, 8)],
}
N_POS_ATTRS = {p: 4 for p in POSITIONS}
N_POS_ATTRS["QB"] = 6
N_POS_ATTRS["K"] = 2
N_POS_ATTRS["P"] = 2

MENTAL_HIGH_AWARENESS = {"QB", "FS", "SS", "MLB", "C"}
MENTAL_PRIORS_TAIL = [(56.0, 9.0), (55.0, 10.0), (58.0, 11.0), (58.0, 10.0), (52.0, 11.0)]
MENTAL_BASE_LEVEL = 69.5        # PositionPhysicalProfile.baseLevel
SOFT_CEILING_PIVOT = 92.0


def soft_ceiling(v: float, pivot: float = SOFT_CEILING_PIVOT, ceiling: float = 99.0) -> float:
    if v <= pivot:
        return v
    headroom = ceiling - pivot
    return pivot + headroom * math.tanh((v - pivot) / headroom)


def clamp_int(v: float, lo: int = 25, hi: int = 99) -> int:
    return min(hi, max(lo, int(round(v))))


def age_level_shift(age: int, pos: str) -> float:
    """LeagueGenerator.ageLevelShift — the level curve the engine sustains."""
    lo, hi = PEAK_AGE[pos]
    if age >= lo:
        past = max(0, age - hi)
        return 11.0 - past * 1.2
    span = max(1.0, lo - 21.0)
    prog = min(1.0, max(0.0, (age - 21.0) / span))
    return -6.0 + (11.0 - (-6.0)) * prog


def veteran_level_shift(depth_index: int) -> float:
    return 3.0 if depth_index == 0 else (0.0 if depth_index == 1 else -3.0)


def pos_attr_range(depth_index: int) -> tuple:
    if depth_index == 0:
        return (75, 95)
    if depth_index == 1:
        return (60, 80)
    return (50, 70)


def reference_overall(rng: random.Random, pos: str, depth_index: int, age: int) -> int:
    """One draw of `Player.overall` exactly as LeagueGenerator would produce it."""
    shift = int(round(age_level_shift(age, pos)))
    vshift = veteran_level_shift(depth_index)

    lo, hi = pos_attr_range(depth_index)
    lo = min(99, max(1, lo + shift))
    hi = min(99, max(lo, hi + shift))
    n = N_POS_ATTRS[pos]
    pos_avg = sum(rng.randint(lo, hi) for _ in range(n)) / n

    level = vshift + shift
    priors = PHYS_PRIORS[pos] + [_STAM, _DUR]
    phys_avg = sum(clamp_int(soft_ceiling(rng.gauss(m + level, s)))
                   for m, s in priors) / 6.0

    aw = 62.0 if pos in MENTAL_HIGH_AWARENESS else 56.0
    mprior = [(aw, 9.0)] + MENTAL_PRIORS_TAIL
    mshift = (MENTAL_BASE_LEVEL + vshift + shift) - (sum(m for m, _ in mprior) / 6.0)
    mental_avg = sum(clamp_int(rng.gauss(m + mshift, s)) for m, s in mprior) / 6.0

    return int(round(pos_avg * 0.5 + phys_avg * 0.3 + mental_avg * 0.2))


def generator_age(rng: random.Random, pos: str) -> int:
    lo, hi = CAREER_AGE_SPAN[pos]
    return min(rng.randint(lo, hi), rng.randint(lo, hi))


def blueprint_league_mean() -> float:
    """League mean OVR of the actual random `LeagueGenerator` league — the
    binding calibration anchor (~76.46)."""
    rng = seeded("blueprint")
    vals = []
    for _ in range(400):
        for pos, count in ROSTER_BLUEPRINT:
            for idx in range(count):
                vals.append(reference_overall(rng, pos, min(idx, 2),
                                              generator_age(rng, pos)))
    return statistics.mean(vals)


def blueprint_tier_means() -> dict:
    """Per depth-index mean OVR of the random `LeagueGenerator` league —
    the tier structure the template has to reproduce."""
    rng = seeded("blueprint-tiers")
    buckets = defaultdict(list)
    for _ in range(300):
        for pos, count in ROSTER_BLUEPRINT:
            for idx in range(count):
                d = min(idx, 2)
                buckets[d].append(reference_overall(rng, pos, d, generator_age(rng, pos)))
    return {d: statistics.mean(v) for d, v in buckets.items()}


def veteran_potential(rng: random.Random, overall: int, age: int, pos: str) -> int:
    """LeagueGenerator.veteranPotential — phase-2 age-anchored veteran ceiling."""
    peak_hi = PEAK_AGE[pos][1]
    if age > peak_hi:
        return min(99, overall + rng.randint(0, 3))
    mu = max(2.0, 14.0 - 2.5 * max(0, age - 22))
    upside = max(0.0, rng.gauss(mu, 4.0))
    return min(99, overall + int(round(upside)))


# ---------------------------------------------------------------------------
# 3. Position families + production heuristics
#
#    Every family below turns a raw season row into a set of named metrics.
#    Each metric is converted to a PERCENTILE inside (family, year) — never an
#    absolute number — so eras, rule changes and pace differences wash out and
#    only "how good was he relative to his peers that year" survives. The
#    weights are the documented position heuristics.
# ---------------------------------------------------------------------------

FAMILY_OF = {
    "QB": "QB", "RB": "RB", "FB": "RB", "WR": "WR", "TE": "TE",
    "LT": "OL", "LG": "OL", "C": "OL", "RG": "OL", "RT": "OL",
    "DE": "DL", "DT": "DL", "OLB": "LB", "MLB": "LB",
    "CB": "DB", "FS": "DB", "SS": "DB", "K": "K", "P": "P",
}

# metric -> weight, per family. Weights sum to 1.0 inside a family.
METRIC_WEIGHTS = {
    "QB": {"rating": 0.30, "ypa": 0.18, "tdint": 0.17, "passYpg": 0.23, "rushProd": 0.12},
    "RB": {"scrimYpg": 0.42, "ypc": 0.20, "touchesPg": 0.24, "recProd": 0.14},
    "WR": {"recYpg": 0.44, "recPg": 0.19, "tgtPg": 0.20, "ypr": 0.17},
    "TE": {"recYpg": 0.40, "recPg": 0.20, "tgtPg": 0.22, "ypr": 0.18},
    "OL": {"snapShare": 0.52, "snapsPg": 0.26, "cleanPlay": 0.22},
    "DL": {"sackPg": 0.34, "tflPg": 0.20, "tklPg": 0.14, "snapShare": 0.26, "ffPg": 0.06},
    "LB": {"tklPg": 0.33, "sackPg": 0.15, "tflPg": 0.12, "coverPg": 0.14, "snapShare": 0.26},
    "DB": {"coverPg": 0.30, "tklPg": 0.19, "snapShare": 0.41, "sackPg": 0.10},
    "K":  {"fgPct": 0.52, "fgLong": 0.20, "fgMade": 0.28},
    "P":  {"puntAvg": 0.55, "in20Rate": 0.35, "puntsPg": 0.10},
}


def _f(stats: dict, key: str, default=0.0) -> float:
    v = stats.get(key)
    return float(v) if v is not None else float(default)


def season_metrics(pos: str, row: dict) -> dict:
    """Named production metrics for one raw season row. Value None = not enough
    volume for the metric to mean anything (it is then simply skipped)."""
    fam = FAMILY_OF[pos]
    st = row.get("stats") or {}
    gp = row.get("gp") or 0
    g = max(1.0, float(gp))
    share = row.get("snapShare")
    m = {}

    if fam == "QB":
        att, comp = _f(st, "att"), _f(st, "comp")
        yds, td, itc = _f(st, "yds"), _f(st, "td"), _f(st, "int")
        m["rating"] = _f(st, "rating") if att >= 60 else None
        m["ypa"] = (yds / att) if att >= 60 else None
        m["tdint"] = ((td - 1.5 * itc) / att * 100.0) if att >= 60 else None
        m["passYpg"] = yds / g
        m["rushProd"] = (_f(st, "rushYds") + 20.0 * _f(st, "rushTd")) / g

    elif fam == "RB":
        ratt, ryds = _f(st, "rushAtt"), _f(st, "rushYds")
        rec, recy = _f(st, "rec"), _f(st, "recYds")
        tds = _f(st, "rushTd") + _f(st, "recTd")
        m["scrimYpg"] = (ryds + recy + 20.0 * tds) / g
        m["ypc"] = (ryds / ratt) if ratt >= 40 else None
        m["touchesPg"] = (ratt + rec) / g
        m["recProd"] = (recy + 8.0 * rec) / g

    elif fam in ("WR", "TE"):
        rec, recy, tgt = _f(st, "rec"), _f(st, "recYds"), _f(st, "tgt")
        m["recYpg"] = (recy + 20.0 * _f(st, "recTd")) / g
        m["recPg"] = rec / g
        m["tgtPg"] = tgt / g
        m["ypr"] = (recy / rec) if rec >= 12 else None

    elif fam == "OL":
        snaps = _f(st, "snaps")
        m["snapShare"] = share if share is not None else None
        m["snapsPg"] = snaps / g
        pen = st.get("pen")
        m["cleanPlay"] = (-(float(pen) / snaps * 1000.0)) if (pen is not None and snaps >= 200) else None

    elif fam == "DL":
        m["sackPg"] = _f(st, "sacks") / g
        m["tflPg"] = _f(st, "tfl") / g
        m["tklPg"] = _f(st, "tackles") / g
        m["snapShare"] = share
        m["ffPg"] = _f(st, "ff") / g

    elif fam == "LB":
        m["tklPg"] = _f(st, "tackles") / g
        m["sackPg"] = _f(st, "sacks") / g
        m["tflPg"] = _f(st, "tfl") / g
        m["coverPg"] = (_f(st, "pd") + 2.0 * _f(st, "defInt")) / g
        m["snapShare"] = share

    elif fam == "DB":
        m["coverPg"] = (_f(st, "pd") + 2.5 * _f(st, "defInt")) / g
        m["tklPg"] = _f(st, "tackles") / g
        m["snapShare"] = share
        m["sackPg"] = _f(st, "sacks") / g

    elif fam == "K":
        fga, fgm = _f(st, "fga"), _f(st, "fgm")
        m["fgPct"] = (fgm / fga) if fga >= 10 else None
        m["fgLong"] = _f(st, "long") if fga >= 10 else None
        m["fgMade"] = fgm / g

    elif fam == "P":
        punts = _f(st, "punts")
        m["puntAvg"] = _f(st, "avg") if punts >= 20 else None
        m["in20Rate"] = (_f(st, "in20") / punts) if punts >= 20 else None
        m["puntsPg"] = punts / g

    return m


def season_confidence(row: dict) -> float:
    """How much a season row is allowed to move a player away from league
    median. A four-game cameo says almost nothing; a 17-game full-time role
    says almost everything."""
    gp = row.get("gp") or 0
    share = row.get("snapShare")
    gp_term = min(1.0, gp / 14.0)
    share_term = min(1.0, (share if share is not None else 0.35) / 0.60)
    return max(0.22, 0.60 * gp_term + 0.40 * share_term)


# ---------------------------------------------------------------------------
# 4. Area (sub-attribute) emphasis hints
#
#    `areaHints` are integer DELTAS in rating points around `ratingTarget`,
#    keyed by the game's own position-attribute names. They are mean-zero per
#    player, so applying them cannot move the solved overall — they only tilt
#    the shape (an accurate game-manager QB vs a big-armed gunslinger).
# ---------------------------------------------------------------------------

# keyed by POSITION FAMILY (FB shares the RB block, exactly like the Swift
# `PositionAttributes.runningBack` case).
AREA_ATTRS = {
    "QB": ["armStrength", "accuracyShort", "accuracyMid", "accuracyDeep",
           "pocketPresence", "scrambling"],
    "RB": ["vision", "elusiveness", "breakTackle", "receiving"],
    "WR": ["routeRunning", "catching", "release", "spectacularCatch"],
    "TE": ["blocking", "catching", "routeRunning", "speed"],
    "OL": ["runBlock", "passBlock", "pull", "anchor"],
    "DL": ["passRush", "blockShedding", "powerMoves", "finesseMoves"],
    "LB": ["tackling", "zoneCoverage", "manCoverage", "blitzing"],
    "DB": ["manCoverage", "zoneCoverage", "press", "ballSkills"],
    "K":  ["kickPower", "kickAccuracy"],
    "P":  ["kickPower", "kickAccuracy"],
}

AREA_CAP = 8            # max |delta| in rating points


def _tilt(value, lo, hi):
    """Map a raw value into -1..+1 across the [lo, hi] band."""
    if value is None:
        return 0.0
    if hi <= lo:
        return 0.0
    return max(-1.0, min(1.0, 2.0 * (value - lo) / (hi - lo) - 1.0))


def area_hints(pos: str, career: dict, height_in: int, weight_lb: int) -> dict:
    """Position heuristics: career rate profile + body -> sub-attribute tilt.

    `career` holds volume-weighted career aggregates produced by
    `aggregate_career_rates`.
    """
    fam = FAMILY_OF[pos]
    h = {}

    if fam == "QB":
        comp_pct = career.get("compPct")
        ypa = career.get("ypa")
        sack_rate = career.get("sackRate")
        rush_pg = career.get("rushYdsPg")
        rush_att_pg = career.get("rushAttPg")
        acc = _tilt(comp_pct, 0.58, 0.71)
        arm = _tilt(ypa, 6.0, 8.6)
        mobile = 0.5 * _tilt(rush_pg, 2.0, 38.0) + 0.5 * _tilt(rush_att_pg, 0.8, 6.5)
        pocket = -_tilt(sack_rate, 0.035, 0.105)
        h["armStrength"] = 4.0 * arm - 1.5 * mobile
        h["accuracyShort"] = 4.5 * acc - 1.5 * arm
        h["accuracyMid"] = 2.5 * acc + 1.0 * arm
        h["accuracyDeep"] = 4.0 * arm - 1.0 * acc
        h["pocketPresence"] = 3.5 * pocket - 1.5 * mobile
        h["scrambling"] = 6.0 * mobile

    elif fam == "RB":
        ypc = career.get("ypc")
        rec_share = career.get("recShare")
        td_rate = career.get("rushTdRate")
        power = _tilt(weight_lb, 195.0, 240.0)
        burst = _tilt(ypc, 3.4, 5.2)
        catch = _tilt(rec_share, 0.05, 0.42)
        h["vision"] = 3.0 * burst + 1.0 * power
        h["elusiveness"] = 4.5 * burst - 3.0 * power
        h["breakTackle"] = 5.0 * power + 2.0 * _tilt(td_rate, 0.008, 0.055)
        h["receiving"] = 6.0 * catch - 1.0 * power

    elif fam == "WR":
        catch_rate = career.get("catchRate")
        ypr = career.get("ypr")
        tgt_pg = career.get("tgtPg")
        td_per_rec = career.get("tdPerRec")
        deep = _tilt(ypr, 9.0, 16.0)
        hands = _tilt(catch_rate, 0.52, 0.74)
        vol = _tilt(tgt_pg, 1.0, 9.0)
        size = _tilt(height_in, 69.0, 77.0)
        h["routeRunning"] = 4.0 * vol + 2.0 * hands - 1.0 * deep
        h["catching"] = 5.0 * hands - 1.0 * deep
        h["release"] = 3.0 * deep + 2.0 * size
        h["spectacularCatch"] = 3.5 * deep + 3.0 * _tilt(td_per_rec, 0.02, 0.12)

    elif fam == "TE":
        tgt_pg = career.get("tgtPg")
        ypr = career.get("ypr")
        catch_rate = career.get("catchRate")
        receiver = _tilt(tgt_pg, 0.5, 6.5)
        h["blocking"] = -5.5 * receiver + 2.0 * _tilt(weight_lb, 235.0, 270.0)
        h["catching"] = 4.0 * receiver + 3.0 * _tilt(catch_rate, 0.55, 0.80)
        h["routeRunning"] = 5.0 * receiver
        h["speed"] = 4.0 * _tilt(ypr, 8.0, 14.5) - 2.0 * _tilt(weight_lb, 235.0, 270.0)

    elif fam == "OL":
        edge = 1.0 if pos in ("LT", "RT") else -1.0
        interior_pull = _tilt(weight_lb, 340.0, 290.0)      # lighter -> better puller
        anchor = _tilt(weight_lb, 290.0, 340.0)
        clean = -_tilt(career.get("penPer1000"), 1.0, 7.0)
        h["passBlock"] = 3.5 * edge + 2.5 * clean
        h["runBlock"] = -2.5 * edge + 3.0 * anchor
        h["pull"] = -2.0 * edge + 4.0 * interior_pull
        h["anchor"] = 4.0 * anchor + 1.0 * clean

    elif fam == "DL":
        sack_pg = career.get("sackPg")
        tfl_pg = career.get("tflPg")
        tkl_pg = career.get("tklPg")
        rusher = _tilt(sack_pg, 0.05, 0.75)
        heavy = _tilt(weight_lb, 250.0, 325.0)
        run_d = _tilt(tkl_pg, 1.0, 4.2)
        h["passRush"] = 6.0 * rusher - 1.5 * heavy
        h["blockShedding"] = 3.0 * run_d + 3.0 * heavy + 1.5 * _tilt(tfl_pg, 0.1, 0.9)
        h["powerMoves"] = 4.5 * heavy + 2.0 * rusher
        h["finesseMoves"] = 5.0 * rusher - 4.0 * heavy

    elif fam == "LB":
        tkl_pg = career.get("tklPg")
        sack_pg = career.get("sackPg")
        cover_pg = career.get("coverPg")
        inside = 1.0 if pos == "MLB" else -1.0
        h["tackling"] = 4.5 * _tilt(tkl_pg, 1.5, 6.5) + 1.5 * inside
        h["zoneCoverage"] = 4.0 * _tilt(cover_pg, 0.05, 0.60) + 1.0 * inside
        h["manCoverage"] = 3.0 * _tilt(cover_pg, 0.05, 0.60) - 1.5 * inside
        h["blitzing"] = 6.0 * _tilt(sack_pg, 0.02, 0.55) - 1.0 * inside

    elif fam == "DB":
        cover_pg = career.get("coverPg")
        tkl_pg = career.get("tklPg")
        corner = 1.0 if pos == "CB" else -1.0
        # coverage vs run-support: ball production per game against tackle rate.
        ball = _tilt(cover_pg, 0.15, 1.10)
        support = _tilt(tkl_pg, 1.5, 5.5)
        size = _tilt(height_in, 69.0, 75.0)
        h["manCoverage"] = 4.0 * ball + 2.5 * corner - 2.0 * support
        h["zoneCoverage"] = 3.0 * ball + 2.5 * support - 1.0 * corner
        h["press"] = 3.5 * size + 2.0 * corner + 1.5 * support
        h["ballSkills"] = 6.0 * ball

    elif fam == "K":
        h["kickPower"] = 6.0 * _tilt(career.get("fgLong"), 48.0, 60.0)
        h["kickAccuracy"] = 6.0 * _tilt(career.get("fgPct"), 0.74, 0.92)

    elif fam == "P":
        h["kickPower"] = 6.0 * _tilt(career.get("puntAvg"), 42.0, 51.0)
        h["kickAccuracy"] = 6.0 * _tilt(career.get("in20Rate"), 0.28, 0.48)

    keys = AREA_ATTRS[fam]     # FB shares the RB attribute block, as in Swift
    vals = {k: h.get(k, 0.0) for k in keys}
    mean = sum(vals.values()) / len(vals)
    out = {}
    for k in keys:
        d = vals[k] - mean                       # mean-zero: cannot move overall
        out[k] = int(max(-AREA_CAP, min(AREA_CAP, round(d))))
    # rounding can reintroduce a small bias; shave it off the largest entry
    bias = sum(out.values())
    if bias != 0:
        victim = max(keys, key=lambda k: abs(out[k]))
        out[victim] = int(max(-AREA_CAP, min(AREA_CAP, out[victim] - bias)))
    return out


def aggregate_career_rates(pos: str, seasons: list) -> dict:
    """Volume-weighted career rate profile, recency-tilted, feeding `area_hints`."""
    fam = FAMILY_OF[pos]
    acc = defaultdict(float)
    for row in seasons:
        st = row.get("stats") or {}
        w = 0.80 ** max(0, SNAPSHOT_YEAR - row["year"])
        gp = max(1.0, float(row.get("gp") or 1))
        acc["gp"] += w * gp
        for k, v in st.items():
            if isinstance(v, (int, float)):
                acc[k] += w * float(v)
        if row.get("snapShare") is not None:
            acc["_shareW"] += w * gp
            acc["_share"] += w * gp * float(row["snapShare"])

    out = {}
    gp = max(1.0, acc["gp"])
    if fam == "QB":
        att = acc["att"]
        out["compPct"] = (acc["comp"] / att) if att >= 100 else None
        out["ypa"] = (acc["yds"] / att) if att >= 100 else None
        out["sackRate"] = (acc["sacked"] / (att + acc["sacked"])) if att >= 100 else None
        out["rushYdsPg"] = acc["rushYds"] / gp
        out["rushAttPg"] = acc["rushAtt"] / gp
    elif fam == "RB":
        ratt = acc["rushAtt"]
        touches = ratt + acc["rec"]
        out["ypc"] = (acc["rushYds"] / ratt) if ratt >= 60 else None
        out["recShare"] = (acc["rec"] / touches) if touches >= 40 else None
        out["rushTdRate"] = (acc["rushTd"] / ratt) if ratt >= 60 else None
    elif fam in ("WR", "TE"):
        rec, tgt = acc["rec"], acc["tgt"]
        out["catchRate"] = (rec / tgt) if tgt >= 30 else None
        out["ypr"] = (acc["recYds"] / rec) if rec >= 20 else None
        out["tgtPg"] = tgt / gp
        out["tdPerRec"] = (acc["recTd"] / rec) if rec >= 20 else None
    elif fam == "OL":
        snaps = acc["snaps"]
        out["penPer1000"] = (acc["pen"] / snaps * 1000.0) if snaps >= 500 else None
    elif fam in ("DL", "LB", "DB"):
        out["sackPg"] = acc["sacks"] / gp
        out["tflPg"] = acc["tfl"] / gp
        out["tklPg"] = acc["tackles"] / gp
        out["coverPg"] = (acc["pd"] + 2.0 * acc["defInt"]) / gp
    elif fam == "K":
        fga = acc["fga"]
        out["fgPct"] = (acc["fgm"] / fga) if fga >= 20 else None
        out["fgLong"] = (acc["long"] / max(1, len(seasons))) if fga >= 20 else None
    elif fam == "P":
        punts = acc["punts"]
        out["puntAvg"] = (acc["avg"] / max(1, len(seasons))) if punts >= 40 else None
        out["in20Rate"] = (acc["in20"] / punts) if punts >= 40 else None
    return out


# ---------------------------------------------------------------------------
# 5. Anonymization assets
# ---------------------------------------------------------------------------

NAME_SUFFIXES = {"Jr.", "Jr", "Sr.", "Sr", "II", "III", "IV", "V"}

# --- dev profile: real-adjacent team nicknames (real city kept) -------------
# Close enough that a developer reads the roster as "that team", far enough that
# no NFL trademark is reproduced. DEV BUILDS ONLY.
DEV_NICKNAMES = {
    "ARI": "Redbirds",   "ATL": "Falconers",  "BAL": "Blackbirds", "BUF": "Bisons",
    "CAR": "Cougars",    "CHI": "Grizzlies",  "CIN": "Tigers",     "CLE": "Bulldogs",
    "DAL": "Wranglers",  "DEN": "Mustangs",   "DET": "Pride",      "GB": "Packmen",
    "HOU": "Rangers",    "IND": "Stallions",  "JAX": "Jaguarundis", "KC": "Monarchs",
    "LA": "Bighorns",    "LAC": "Voltage",    "LV": "Marauders",   "MIA": "Porpoises",
    "MIN": "Norsemen",   "NE": "Minutemen",   "NO": "Sinners",     "NYG": "Colossus",
    "NYJ": "Jetstream",  "PHI": "Ospreys",    "PIT": "Ironmen",    "SEA": "Kingfishers",
    "SF": "Miners",      "TB": "Corsairs",    "TEN": "Comets",     "WAS": "Sentinels",
}

# --- publish profile: fully fictional nicknames (real city kept) -----------
PUBLISH_NICKNAMES = {
    "ARI": "Sunspires",  "ATL": "Ironclads",  "BAL": "Harbormen",  "BUF": "Blizzard",
    "CAR": "Foxhounds",  "CHI": "Ironworks",  "CIN": "Riverkings", "CLE": "Forgemen",
    "DAL": "Longriders", "DEN": "Summit",     "DET": "Motorworks", "GB": "Timberjacks",
    "HOU": "Astronauts", "IND": "Speedway",   "JAX": "Tidewater",  "KC": "Stockyards",
    "LA": "Pacifics",    "LAC": "Currents",   "LV": "Highrollers", "MIA": "Reefsharks",
    "MIN": "Nordics",    "NE": "Colonials",   "NO": "Krewe",       "NYG": "Skyline",
    "NYJ": "Aviators",   "PHI": "Bellringers", "PIT": "Steelworks", "SEA": "Evergreens",
    "SF": "Goldrush",    "TB": "Freebooters", "TEN": "Cumberlands", "WAS": "Monuments",
}

# Cities / app-side abbreviations (game canon: LA Rams = "LAR").
CITY_OF = {
    "ARI": "Arizona", "ATL": "Atlanta", "BAL": "Baltimore", "BUF": "Buffalo",
    "CAR": "Carolina", "CHI": "Chicago", "CIN": "Cincinnati", "CLE": "Cleveland",
    "DAL": "Dallas", "DEN": "Denver", "DET": "Detroit", "GB": "Green Bay",
    "HOU": "Houston", "IND": "Indianapolis", "JAX": "Jacksonville",
    "KC": "Kansas City", "LA": "Los Angeles", "LAC": "Los Angeles",
    "LV": "Las Vegas", "MIA": "Miami", "MIN": "Minnesota", "NE": "New England",
    "NO": "New Orleans", "NYG": "New York", "NYJ": "New York",
    "PHI": "Philadelphia", "PIT": "Pittsburgh", "SEA": "Seattle",
    "SF": "San Francisco", "TB": "Tampa Bay", "TEN": "Tennessee",
    "WAS": "Washington",
}
APP_ABBR = {k: k for k in CITY_OF}
APP_ABBR["LA"] = "LAR"

# --- publish name pools ----------------------------------------------------
# Independent of the real names (spec section 1: no derivation, no rhythm
# matching). Deliberately broad culturally so rosters read authentic in
# aggregate, exactly like `RandomNameGenerator`'s pools — but far larger, and
# every entry is filtered at runtime against the real-name blocklist.
PUB_FIRST = """
Alaric Alonso Andre Arlo Armond Ashton Aurelio Barrett Baxter Bennett
Bishop Blaise Bodie Boone Bram Braylen Brennan Brixton Broderick Cade
Caleb Callum Camden Carmine Cassius Cedric Cormac Cortez Corvin Cyprien
Cyrus Dallin Damarion Damir Darian Dashawn Dashiell Davion Deacon Declan
Delmar Demetri Deshun Devanti Dominik Donovan Dorian Draven Duncan Eamon
Easton Eero Elias Ellison Emeka Emerson Emiliano Emrys Enzo Ezekiel Fabian
Faron Fenwick Ferris Finnian Fletcher Gage Galen Garrison Garvey Gideon
Grady Granger Hadrian Hakeem Halston Harlan Hayden Hollan Hollis Ibrahim
Idris Ignacio Ilan Immanuel Isaias Ivo Jace Jaden Jamari Jarell Jarreth
Jaxon Jeremiah Jericho Jibril Joaquin Jonas Jonquil Jovan Judah Kaeden
Kai Kaleo Kamari Kane Kason Kaspar Keanu Kellen Kenji Keon Kester Kieran
Killian Kolton Kwabena Lachlan Lazaro Leander Legend Lennox Leonel Linus
Lior Lorenzo Lorne Luca Lucian Ludovic Maceo Maddox Magnus Malachi Manoa
Marcelo Marius Mateo Maverick Maxton Merrick Merrit Miles Milo Moises
Montrell Mordecai Nakoa Nasir Nehemiah Neville Nikolai Noel Nolan Norbert
Obadiah Octavio Odalric Onyx Orion Orrin Osman Osric Pascal Patrice Paxton
Pell Phineas Quade Quentin Quillon Quinton Rafferty Raiden Ramiro Raylan
Reece Remington Renzo Rhett Ricardo Ridge Ridley Riggs Roan Rocco Roderick
Rohan Roman Ronan Rowan Ruben Sabastian Saul Sawyer Sebastien Seneca Sidney
Silas Sincere Solomon Soren Sorin Stellan Sullivan Tadeo Talon Tarik Tavian
Tavish Teagan Terrance Thaddeus Theo Tiago Tobias Tomas Torrance Trace
Trenton Tristan Ulises Umberto Uriah Valen Vaughn Verner Vicente Vincent
Wade Waylon Wendell Weston Whitaker Wilder Wilkes Wyatt Xander Yahir Yannick
Yosef Zachariah Zaire Zander Zavier Zayn Zeke Zenon Zephan
""".split()

PUB_LAST = """
Abernathy Ackerly Adkerson Alderman Alvarenga Amsler Ansley Applewhite Arbogast
Ardmore Ashcombe Ashworth Attaway Auchter Averill Balfour Ballinger Bannister
Barlowe Bascomb Battaglia Beauchene Beckwith Bellamy Bennington Berrigan Bidwell
Billingsley Birdsall Blackwood Blakeney Blanchfield Boatwright Bogardus
Bolliger Bonaventure Boruff Bosworth Bourgeois Bracewell Bradbury Braithwaite
Brantley Breckenridge Brightwell Brimmer Broadwater Brockway Bromfield
Brundage Buckminster Burkhalter Burnham Burroughs Cadwallader Calloway Candelaria
Canfield Cantwell Carbajal Cardarelli Carrington Cartwright Castellano Cauthen
Chamberlain Charbonneau Chastain Chenoweth Chesterfield Chevalier Cifuentes
Claiborne Clarkston Clatterbuck Clemmons Cloutier Colgrove Comstock Copperfield
Cordoba Corrigan Cortright Coventry Cranfield Crenshaw Crisanti Crosswhite 
Cunliffe Cuthbertson Dalrymple Danforth Darlington Daugherty Delacroix
Dellinger Demarest Denbrough Derringer Devereaux Dillingham Dinsmore Dockery Dolliver
Doubleday Dowdell Draycott Dumbarton Dunwoody Eastbrook Eberhardt Edgerton
Eichelberger Ellsworth Elmendorf Embleton Endicott Engelhardt Escalante Estabrook
Ethridge Fairbairn Fairweather Falkenrath Farnsworth Featherstone Fenwick Ferrante
Fetterman Fitzhugh Fontenot Forrester Fothergill Frankland Fredricks
Frobisher Fullerton Gainsborough Galbraith Gallardo Gambrell Gantry Garfinkel
Garrity Gatlin Gauthier Gearhart Gilliland Glassman Goddard Golightly Goodnight
Gorsuch Grantham Greenhalgh Gresham Grimsley Grosvenor Hadfield
Halloran Hambleton Hammersmith Hanneman Harcourt Hardesty Harkness Harrington
Hartigan Haverford Hawthorne Heatherly Hedgepeth Henshaw Hepworth
Hetherington Hidalgo Highsmith Hildebrand Hillenbrand Hinsdale Hollingsworth
Holmquist Honeycutt Hopewell Hornbeck Houghton Hovland Hubbell Huddleston Hutchings
Ingersoll Inglewood Ironside Isaksen Jaramillo Jessup Jimison Jorgensen Kaminski
Karrington Kearsley Kellerman Kendrew Kenworthy Kerrigan Kesterson Killingsworth
Kimbrough Kingsbury Kirkbride Kittredge Klingman Kohlmeier Kornegay
Kristiansen Ladbroke Lambourne Lanphier Larrabee Latimer Laurelwood Leatherwood
Ledbetter Lemoine Lightfoot Lindqvist Linthicum Littlefield Livingston Lockridge
Loftin Longstreth Lovegrove Lundgren Lyndhurst Macalister Maddocks Magnusson
Mainwaring Malcolmson Manzanares Marchetti Markham Marsden Mathison Maycomb
Meacham Medlock Mendenhall Merriweather Middlebrook Milburn Millgate
Modisette Montague Moorcroft Morningstar Mortenson Mulholland Mullenax Nadeau
Nantwich Narvaez Netherton Newcomb Nightingale Norcross Northrup Oakhurst Oberlin
Ogletree Oldenburg Ormsby Osgood Ostrander Ottinger Overstreet Paddington Pallister
Pankhurst Papadakis Pemberton Pennington Peppercorn Petitjean Pettigrew Pfeiffer
Pickford Pilkington Plumstead Poindexter Pomeroy Poteet Prudhomme
Quarterman Quillen Quintanilla Radcliffe Ragsdale Rainwater Ravenscroft Reddington
Reinholt Renshaw Restrepo Rhinehart Ridgeway Rigsbee Rittenhouse Riverton
Rockhold Rothbury Rountree Rutherford Sackville Saddington Satterfield
Saylor Scarborough Schellenberg Schwarzkopf Selwyn Shackleford Sharpsteen Shelburne
Shirtliff Sidebottom Silverthorne Skillman 
Smallwood Somerville Southgate Sparrowhawk Standish Stapleton Steadman
Stellenbosch Stillwater Stockbridge Stonebraker Stovall Studebaker
Sturbridge Sudderth Summerfield Sutherland Swearingen Sweetland Tanberg Tanguay
Tarrington Tewksbury Thistlewood Thorvald Threadgill Tillinghast Tinsley
Tolliver Torrington Trafford Trimberger Truesdale Tunstall Twitchell
Underhill Upshaw Vandenberg Vanterpool Varnadoe Verrazano Vestergaard
Villalobos Vosburgh Wadsworth Wainwright Waldgrave Wallingford
Wamsley Wanamaker Warrington Waterhouse Weatherby Wendover Wetherell Whitcomb
Whittington Wickersham Wigglesworth Willoughby Wimberly Winchester
Windham Wingfield Winterbourne Wolverton Woodbridge Woolridge Wrenfield Wycliffe
Yarborough Yeardley Yorkston Zabriskie Zumwalt
""".split()

# Notable NFL names of roughly the last 15 years that are NOT on the 2026
# rosters. Together with every name in the raw data this forms the blocklist.
NOTABLE_PAST = """
Tom Brady;Peyton Manning;Eli Manning;Drew Brees;Ben Roethlisberger;Philip Rivers
Aaron Rodgers;Russell Wilson;Cam Newton;Andrew Luck;Matt Ryan;Carson Palmer
Tony Romo;Alex Smith;Jay Cutler;Joe Flacco;Ryan Fitzpatrick;Colin Kaepernick
Robert Griffin;Marcus Mariota;Jameis Winston;Blake Bortles;Sam Bradford
Adrian Peterson;Marshawn Lynch;LeSean McCoy;Frank Gore;Jamaal Charles
Arian Foster;DeMarco Murray;Le'Veon Bell;Todd Gurley;Ezekiel Elliott
Matt Forte;Chris Johnson;Ray Rice;Maurice Jones-Drew;Steven Jackson
Calvin Johnson;Larry Fitzgerald;Andre Johnson;Julio Jones;Antonio Brown
Demaryius Thomas;Dez Bryant;Brandon Marshall;Roddy White;Wes Welker
Julian Edelman;Reggie Wayne;Steve Smith;Anquan Boldin;Vincent Jackson
Rob Gronkowski;Jimmy Graham;Jason Witten;Antonio Gates;Greg Olsen
Tony Gonzalez;Vernon Davis;Delanie Walker;Zach Ertz;Kyle Rudolph
J.J. Watt;Von Miller;Khalil Mack;Aaron Donald;Justin Houston;Cameron Wake
Julius Peppers;Jared Allen;Terrell Suggs;Elvis Dumervil;Robert Quinn
Ndamukong Suh;Gerald McCoy;Fletcher Cox;Geno Atkins;Kawann Short
Luke Kuechly;NaVorro Bowman;Patrick Willis;Bobby Wagner;Lavonte David
Thomas Davis;Sean Lee;Ryan Shazier;C.J. Mosley;Deion Jones
Darrelle Revis;Richard Sherman;Patrick Peterson;Joe Haden;Aqib Talib
Chris Harris;Xavier Rhodes;Josh Norman;Stephon Gilmore;Casey Hayward
Earl Thomas;Kam Chancellor;Eric Berry;Harrison Smith;Devin McCourty
Eric Weddle;Reshad Jones;Landon Collins;Malcolm Jenkins;Tyrann Mathieu
Joe Thomas;Jason Peters;Tyron Smith;Trent Williams;Duane Brown
Zack Martin;Marshal Yanda;Maurkice Pouncey;Alex Mack;Travis Frederick
Justin Tucker;Adam Vinatieri;Stephen Gostkowski;Matt Prater;Sebastian Janikowski
Johnny Hekker;Shane Lechler;Thomas Morstead;Pat McAfee
Terrell Owens;Randy Moss;Ray Lewis;Ed Reed;Champ Bailey;Charles Woodson
Brian Urlacher;Jason Taylor;Dwight Freeney;Kevin Williams;Vince Wilfork
LaDainian Tomlinson;Brian Westbrook;Willis McGahee;Michael Turner
Hines Ward;Chad Johnson;Santonio Holmes;Mike Wallace;Percy Harvin
Bill Belichick;Pete Carroll;Andy Reid;John Harbaugh;Jim Harbaugh
Sean Payton;Mike Tomlin;Bruce Arians;Ron Rivera;Doug Pederson
Jon Gruden;Rex Ryan;Chip Kelly;Gary Kubiak;Mike Shanahan;Wade Phillips
Dick LeBeau;Monte Kiffin;Buddy Ryan;Norv Turner;Mike Martz
""".replace("\n", ";").split(";")
NOTABLE_PAST = [n.strip() for n in NOTABLE_PAST if n.strip()]

# --- college tier tables ---------------------------------------------------
P5_COLLEGES = """
Alabama;Ohio State;Georgia;Michigan;Notre Dame;LSU;Texas;Penn State;Clemson;Iowa
Stanford;Washington;Florida;Oklahoma;UCLA;Oregon;Texas A&M;Miami;Auburn;Tennessee
USC;South Carolina;Wisconsin;North Carolina;Maryland;Kentucky;Florida State
Boston College;Virginia Tech;Minnesota;TCU;N.C. State;Illinois;California
Mississippi;Utah;Oklahoma State;Arkansas;Missouri;Oregon State;Iowa State
Syracuse;Wake Forest;Mississippi State;Texas Tech;Pittsburgh;Duke;Louisville
Kansas State;Purdue;Michigan State;Virginia;Arizona;West Virginia;Rutgers
Nebraska;Northwestern;Baylor;Indiana;Arizona State;Kansas;Colorado;Georgia Tech
Vanderbilt;Washington State;SMU;Cincinnati;Houston;BYU;UCF
""".replace("\n", ";").split(";")
P5_COLLEGES = [c.strip() for c in P5_COLLEGES if c.strip()]

G5_COLLEGES = """
Boise State;Memphis;Tulane;Toledo;Western Michigan;Wyoming;Appalachian State
San Diego State;Buffalo;Western Kentucky;Southern Mississippi;Utah State;Troy
Louisiana-Lafayette;Florida Atlantic;Fresno State;Tulsa;UAB;Connecticut;Marshall
Nevada;Bowling Green;South Alabama;Texas-San Antonio;Texas-El Paso;Eastern Michigan
Rice;Charlotte;Louisiana Tech;Central Michigan;Temple;Air Force;Army;Navy
Middle Tennessee State;East Carolina;Georgia State;Georgia Southern;North Texas
San Jose State;Florida International;UNLV;Ohio;Kent State;Akron;Ball State
Northern Illinois;Miami (OH);Colorado State;New Mexico;Hawaii;Arkansas State
Coastal Carolina;James Madison;Liberty;Old Dominion;Jacksonville State;Sam Houston State
""".replace("\n", ";").split(";")
G5_COLLEGES = [c.strip() for c in G5_COLLEGES if c.strip()]

FCS_COLLEGES = """
North Dakota State;South Dakota State;Montana State;Montana;Eastern Washington
Weber State;Northern Iowa;Illinois State;Southern Illinois;Youngstown State
Villanova;Delaware;Richmond;William & Mary;Elon;Furman;Mercer;Samford
Chattanooga;Wofford;The Citadel;Harvard;Yale;Princeton;Penn;Dartmouth;Columbia
Holy Cross;Colgate;Lafayette;Fordham;Maine;New Hampshire;Rhode Island;Albany
Stony Brook;Sacred Heart;Central Arkansas;Stephen F. Austin State;Tarleton State
Abilene Christian;Lamar;McNeese State;Nicholls State;Southeastern Louisiana
Alcorn State;Jackson State;Florida A&M;South Carolina State;Howard;Morgan State
North Carolina Central;Tennessee State;Grambling State;Prairie View A&M
Southern University;Alabama A&M;Alabama State;Bethune-Cookman;Norfolk State
Idaho;Portland State;Cal Poly;UC Davis;Sacramento State;North Dakota;South Dakota
Missouri State;Indiana State;Western Illinois;Murray State;Austin Peay
Ferris State;Grand Valley State;Northwest Missouri State;Minnesota State
Saginaw Valley State;Lenoir Rhyne;Wingate;Valdosta State;Colorado Mesa
Angelo State;Missouri Western;Washburn;Findlay;Tusculum College;Shepherd
""".replace("\n", ";").split(";")
FCS_COLLEGES = [c.strip() for c in FCS_COLLEGES if c.strip()]


def primary_college(name: str) -> str:
    """nflverse lists transfer chains newest-school-FIRST ("LSU; Ohio State",
    "Colorado; Jackson State University"), so the school of record is the head
    of the chain, not the tail."""
    if not name:
        return NO_COLLEGE
    return name.split(";")[0].strip() or NO_COLLEGE


def college_tier(name: str) -> str:
    if not name or name == NO_COLLEGE:
        return "FCS"
    primary = primary_college(name)
    if primary in P5_COLLEGES:
        return "P5"
    if primary in G5_COLLEGES:
        return "G5"
    return "FCS"


# ---------------------------------------------------------------------------
# 6. String helpers (Levenshtein, name morphing)
# ---------------------------------------------------------------------------


def levenshtein_at_most(a: str, b: str, limit: int) -> int:
    """Bounded edit distance: returns the true distance, or `limit + 1` once it
    is provably greater. Length pre-filter makes the blocklist scan cheap."""
    if abs(len(a) - len(b)) > limit:
        return limit + 1
    if a == b:
        return 0
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        best = i
        for j, cb in enumerate(b, 1):
            cost = 0 if ca == cb else 1
            v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            cur.append(v)
            best = min(best, v)
        if best > limit:
            return limit + 1
        prev = cur
    return prev[-1]


def norm_name(s: str) -> str:
    return re.sub(r"[^a-z]", "", s.lower())


def split_name(full: str):
    """-> (first, middle_last_without_suffix, suffix_or_empty)"""
    toks = full.split()
    suffix = ""
    if toks and toks[-1] in NAME_SUFFIXES:
        suffix = toks[-1]
        toks = toks[:-1]
    if len(toks) == 1:
        return toks[0], "", suffix
    return toks[0], " ".join(toks[1:]), suffix


ONSET_RE = re.compile(r"^([^aeiouAEIOU]*)(.*)$")
VOWEL_SHIFT = {"a": "e", "e": "a", "i": "y", "o": "u", "u": "o", "y": "i"}


def _onset(word: str):
    m = ONSET_RE.match(word)
    return m.group(1), m.group(2)


def _texture(word: str, rng: random.Random) -> str:
    """One small deterministic phonetic tweak that keeps rhythm and syllable
    count. Never creates a triple letter and never touches the first two
    characters, so the onset that carries the sound-alike stays intact."""
    if len(word) < 4:
        return word + rng.choice(["n", "s", "k"])
    roll = rng.randrange(10)                         # doubling and vowel shifts
    choice = 0 if roll < 5 else (1 if roll < 9 else 2)   # dominate; codas are rare
    if choice == 0:                                  # double a medial consonant
        for i in range(2, len(word) - 1):
            ch = word[i].lower()
            if (ch not in "aeiouy'-." and ch != word[i - 1].lower()
                    and ch != word[i + 1].lower()):
                return word[:i] + word[i] + word[i:]
        choice = 1
    if choice == 1:                                  # shift the first inner vowel
        for i, ch in enumerate(word):
            if i > 0 and ch.lower() in VOWEL_SHIFT:
                rep = VOWEL_SHIFT[ch.lower()]
                return word[:i] + (rep.upper() if ch.isupper() else rep) + word[i + 1:]
        choice = 2
    if word[-1].lower() in "aeiouy":                 # alter the coda
        return word + rng.choice(["n", "s", "th", "l"])
    return word + rng.choice(["e", "y", "on", "en"])


def _join_onset(onset: str, body: str) -> str:
    """Glue a borrowed onset onto a name body without doubling its capital."""
    if not body:
        return onset
    body = body[0].lower() + body[1:]
    joined = onset + body
    return joined[0].upper() + joined[1:]


FALLBACK_ONSETS = ["B", "Br", "C", "Ch", "D", "Dr", "F", "Fl", "G", "Gr", "H",
                   "J", "K", "Kr", "L", "M", "N", "P", "Pr", "R", "S", "Sh",
                   "St", "T", "Tr", "V", "W"]


def dev_morph(full_name: str, salt: str) -> str:
    """devProfile sound-alike morph — the documented rule:

        1. split into first / last-head / trailing tokens (suffix preserved);
        2. SWAP the onset consonant clusters between first and last-head —
           "Jared Goff" -> "Gared Joff" (a vowel-initial half borrows a seeded
           onset instead, so "Amon-Ra Brown" cannot decay to "Own");
        3. apply one seeded phonetic texture tweak to each half — double a
           medial consonant, shift a vowel, alter the coda, or transpose the
           final pair -> "Garret Joff";
        4. reject anything that normalises back to the real name and re-draw.

    Syllable counts and rhythm survive, so the name reads as "that guy" to the
    developer and to nobody else. DEV BUILDS ONLY — never shipped.
    """
    first, last, suffix = split_name(full_name)
    if not last:
        last, first = first, "Ray"
    last_tokens = last.split()
    last_head = last_tokens[-1]
    last_prefix = last_tokens[:-1]          # "St." in "St. Brown", "Van" in "Van Ginkel"

    base_rng = seeded("devonset", salt, full_name)
    initials_only = bool(re.fullmatch(r"(?:[A-Z]\.)+", first))
    if initials_only:
        letters = "ABCDEFGHJKLMRTVW"
        first = f"{base_rng.choice(letters)}.{base_rng.choice(letters)}."
        f_on, f_body = base_rng.choice(FALLBACK_ONSETS), ""
    else:
        f_on, f_body = _onset(first)
        if not f_on:
            f_on = base_rng.choice(FALLBACK_ONSETS)

    l_on, l_body = _onset(last_head)
    if not l_on:
        l_on = base_rng.choice(FALLBACK_ONSETS)

    new_first = _join_onset(l_on, f_body) if f_body else first
    new_last = _join_onset(f_on, l_body) if l_body else _join_onset(f_on, last_head)

    for attempt in range(24):
        rng = seeded("devmorph", salt, full_name, attempt)
        cand_first = _texture(new_first, rng) if f_body else new_first
        cand_last = _texture(new_last, rng)
        parts = [cand_first] + last_prefix + [cand_last]
        if suffix:
            parts.append(suffix)
        out = " ".join(parts)
        if norm_name(out) != norm_name(full_name):
            return out
    return " ".join([new_first] + last_prefix + [new_last] + ([suffix] if suffix else []))


# ---------------------------------------------------------------------------
# 7. Load raw + build the blocklist
# ---------------------------------------------------------------------------


def load_raw(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def build_blocklist(raw: dict) -> dict:
    """Every real name that must never survive into the publish template."""
    full, last = set(), set()

    def add(name):
        if not name:
            return
        name = name.strip()
        if not name:
            return
        full.add(name)
        _, ln, _ = split_name(name)
        if ln:
            last.add(ln.split()[-1])

    for team in raw["teams"]:
        for p in team["players"]:
            add(p["name"])
    for abbr, staff in raw["staffs"]["staffs"].items():
        for slot in ("headCoach", "offensiveCoordinator", "defensiveCoordinator"):
            s = staff.get(slot)
            if s and s.get("name"):
                add(s["name"])
    for n in NOTABLE_PAST:
        add(n)

    return {
        "full": sorted(full),
        "last": sorted(last),
        "fullNorm": sorted({norm_name(n) for n in full}),
        "lastNorm": sorted({norm_name(n) for n in last if len(n) >= 4}),
    }


# ---------------------------------------------------------------------------
# 8. Ratings derivation
# ---------------------------------------------------------------------------

# QA_REPORT carry-in 1: `role` / `depthChartRank` is a ONE-SEASON VOLUME ranking
# and is wrong in 27 of 768 starter slots. The rate-based production model below
# fixes most of it on its own; these two are forced explicitly because the brief
# names them, and the remaining machine-listed suspects are corrected from the
# raw file's own `qa.depthOrderSuspects` evidence block.
HAND_DEPTH_OVERRIDES = [
    # (team, pos, must_outrank, over, margin_in_score_points, why)
    ("CIN", "QB", "Joe Burrow", "Joe Flacco", 6.0,
     "Franchise QB; led on rate (.878 snap share vs .778) but was out-volumed."),
    ("WAS", "QB", "Jayden Daniels", "Marcus Mariota", 6.0,
     "Franchise QB; led on rate (.903 vs .745) but was out-volumed."),
]

STARTER_QUOTA_HINT = {          # only used to shape the role anchor
    "QB": 1, "RB": 1, "FB": 1, "WR": 3, "TE": 1,
    "LT": 1, "LG": 1, "C": 1, "RG": 1, "RT": 1,
    "DE": 2, "DT": 2, "OLB": 2, "MLB": 1, "CB": 3, "FS": 1, "SS": 1,
    "K": 1, "P": 1,
}
ROLE_BASE = {"starter": 0.80, "rotation": 0.60, "backup": 0.42, "depth": 0.28}


def percentile_tables(raw: dict):
    """For every (family, year, metric): the sorted list of observed values,
    so a raw number can be turned into a peer percentile."""
    buckets = defaultdict(list)
    for team in raw["teams"]:
        for p in team["players"]:
            fam = FAMILY_OF[p["pos"]]
            for row in p["seasons"]:
                for name, val in season_metrics(p["pos"], row).items():
                    if val is None:
                        continue
                    buckets[(fam, row["year"], name)].append(float(val))
    for key in buckets:
        buckets[key].sort()
    return buckets


def pct_of(sorted_vals: list, v: float) -> float:
    """Fraction of the peer group at or below `v`."""
    n = len(sorted_vals)
    if n == 0:
        return 0.5
    lo, hi = 0, n
    while lo < hi:
        mid = (lo + hi) // 2
        if sorted_vals[mid] < v:
            lo = mid + 1
        else:
            hi = mid
    lower = lo
    lo, hi = 0, n
    while lo < hi:
        mid = (lo + hi) // 2
        if sorted_vals[mid] <= v:
            lo = mid + 1
        else:
            hi = mid
    upper = lo
    return (lower + upper) / (2.0 * n)


def season_score(pos: str, row: dict, tables) -> tuple:
    """-> (score in 0..1, confidence in 0..1). 0.5 = league-median season."""
    fam = FAMILY_OF[pos]
    weights = METRIC_WEIGHTS[fam]
    total_w, acc = 0.0, 0.0
    for name, val in season_metrics(pos, row).items():
        if val is None:
            continue
        w = weights.get(name, 0.0)
        if w <= 0:
            continue
        table = tables.get((fam, row["year"], name))
        if not table:
            continue
        acc += w * pct_of(table, float(val))
        total_w += w
    conf = season_confidence(row)
    if total_w <= 0:
        return 0.5, conf * 0.4
    pct = acc / total_w
    return 0.5 + conf * (pct - 0.5), conf


def pedigree_score(draft: dict) -> float:
    if not draft or draft.get("pick") is None:
        if draft and draft.get("round"):
            pick = draft["round"] * 32
        else:
            return 0.12
    else:
        pick = draft["pick"]
    v = max(0.0, min(1.0, 1.0 - (pick - 1) / 260.0))
    return 0.14 + 0.86 * (v ** 0.85)


def derive_scores(raw: dict, tables) -> dict:
    """Per-player quality score in approximate rating points (before calibration)."""
    # 2025 snap-share percentile inside (family, 2025) — the role signal.
    share_tables = defaultdict(list)
    for team in raw["teams"]:
        for p in team["players"]:
            for row in p["seasons"]:
                if row["year"] == SNAPSHOT_YEAR and row.get("snapShare") is not None:
                    share_tables[FAMILY_OF[p["pos"]]].append(float(row["snapShare"]))
    for k in share_tables:
        share_tables[k].sort()

    out = {}
    for team in raw["teams"]:
        for p in team["players"]:
            pos, fam = p["pos"], FAMILY_OF[p["pos"]]
            seasons = p["seasons"]

            # --- production ------------------------------------------------
            num, den = 0.0, 0.0
            for row in seasons:
                s, conf = season_score(pos, row, tables)
                w = (0.62 ** max(0, SNAPSHOT_YEAR - row["year"])) * (0.40 + 0.60 * conf)
                num += w * s
                den += w
            prod = (num / den) if den > 0 else None

            # --- role ------------------------------------------------------
            last = next((r for r in reversed(seasons) if r["year"] == SNAPSHOT_YEAR), None)
            share = (last or {}).get("snapShare")
            share_pct = pct_of(share_tables[fam], float(share)) if share is not None else 0.35
            base = ROLE_BASE.get(p.get("role") or "depth", 0.30)
            dcr = p.get("depthChartRank") or 4
            role = base - 0.045 * (dcr - 1) + 0.28 * (share_pct - 0.5)
            role = max(0.05, min(0.98, role))

            # --- draft pedigree, decaying with experience ------------------
            ped = pedigree_score(p.get("draft"))
            yp = p.get("yearsPro") or 0
            ped_w = 0.32 * math.exp(-yp / 2.2)

            core = (0.60 * prod + 0.40 * role) if prod is not None else role
            quality = (1.0 - ped_w) * core + ped_w * ped

            # Score lives in ~rating points: only its ORDERING matters, because
            # the calibration step below is a rank -> reference-quantile map.
            score = 60.0 + 26.0 * quality + 0.5 * age_level_shift(p["age"], pos)
            out[(team["abbr"], p["name"], pos)] = {
                "score": score, "prod": prod, "role": role, "ped": ped,
                "quality": quality,
            }
    return out


# The QB room is the most visible depth decision in the game, and it is the one
# the raw snapshot gets right: QA_REPORT section 4.1 validated 30 of 32 rooms,
# and the two failures (CIN, WAS) are the hand overrides above. Career
# production percentiles cannot see "the rookie the franchise just drafted
# first overall is the starter" (TEN Cam Ward, NYG Jaxson Dart), so at QB — and
# only at QB — the snapshot's rank-1 man is locked to the top of his room.
# Every other position is ordered purely by the derived ratings, which is what
# QA_REPORT section 4.3 asks for and which measurably beats the raw one-season
# volume ranking (it puts St. Brown, Lamb, Hutchinson and Hendrickson back on
# top of their groups).
QB_STARTER_LOCK = True


def apply_depth_corrections(raw: dict, scores: dict, report: list):
    """QA_REPORT carry-in 1. Depth order must be re-derivable from the ratings,
    so where the raw one-season volume ranking is demonstrably wrong we lift the
    genuinely-better player above the listed starter IN SCORE SPACE (which then
    survives calibration, because calibration is monotone)."""
    fixed = []
    index = {}
    for team in raw["teams"]:
        for p in team["players"]:
            index[(team["abbr"], p["name"])] = (p["pos"], p)

    for team_abbr, pos, better, worse, margin, why in HAND_DEPTH_OVERRIDES:
        kb = (team_abbr, better, pos)
        kw = (team_abbr, worse, pos)
        if kb in scores and kw in scores:
            need = scores[kw]["score"] + margin
            if scores[kb]["score"] < need:
                scores[kb]["score"] = need
            fixed.append(f"HAND {team_abbr} {pos}: {better} > {worse} (+{margin:.1f}) — {why}")

    for s in raw["qa"].get("depthOrderSuspects", []):
        team_abbr, pos = s["team"], s["pos"]
        kb = (team_abbr, s["benched"], pos)
        kw = (team_abbr, s["listedStarter"], pos)
        if kb not in scores or kw not in scores:
            continue
        gap = float(s["benchedSnapShare2025"]) - float(s["starterSnapShare2025"])
        margin = 1.0 + 8.0 * max(0.0, gap)
        need = scores[kw]["score"] + margin
        if scores[kb]["score"] < need:
            scores[kb]["score"] = need
            fixed.append(
                f"QA-suspect {team_abbr} {pos}: {s['benched']} > {s['listedStarter']} (+{margin:.2f})")
    if QB_STARTER_LOCK:
        promoted = {(s["team"], s["pos"]): s["benched"]
                    for s in raw["qa"].get("depthOrderSuspects", [])}
        locked = 0
        for team in raw["teams"]:
            room = [p for p in team["players"] if p["pos"] == "QB"]
            if len(room) < 2:
                continue
            want = promoted.get((team["abbr"], "QB"))
            leader = next((p for p in room if p["name"] == want), None) \
                or next((p for p in room if p.get("depthChartRank") == 1), None)
            if leader is None:
                continue
            lk = (team["abbr"], leader["name"], "QB")
            top = max(scores[(team["abbr"], p["name"], "QB")]["score"]
                      for p in room if p["name"] != leader["name"])
            if scores[lk]["score"] < top + 0.5:
                scores[lk]["score"] = top + 0.5
                locked += 1
        fixed.append(f"QB starter lock: {locked}/32 rooms needed a lift so the "
                     f"snapshot's QB1 tops his room (QA_REPORT section 4.1)")

    report.extend(fixed)
    return fixed


def build_reference_pools(raw: dict) -> dict:
    """Monte-Carlo the Swift generator over THIS league's actual composition —
    same positions, same per-team depth counts, same real ages — and collect the
    resulting OVR distribution per position. Calibrating onto this pool is what
    makes 'the template league sits exactly where the random league sits' true
    rather than aspirational."""
    pools = defaultdict(list)
    rng = seeded("refpool")
    for rep in range(REF_SIM_REPS):
        for team in raw["teams"]:
            by_pos = defaultdict(list)
            for p in team["players"]:
                by_pos[p["pos"]].append(p)
            for pos, plist in by_pos.items():
                ordered = sorted(plist, key=lambda q: q.get("depthChartRank") or 99)
                for idx, _p in enumerate(ordered):
                    pools[pos].append(reference_overall(
                        rng, pos, min(idx, 2), generator_age(rng, pos)))
    for pos in pools:
        pools[pos] = _smooth(sorted(pools[pos]))
    return pools


def _smooth(pool: list) -> list:
    """Spread each block of equal integers uniformly across `v-0.5 .. v+0.5`.

    The pool is a list of integer OVRs, so a raw quantile lookup lands ON the
    lattice; a later global level shift would then round EVERY player the same
    direction (re-introducing the bias the shift removed), and equal mapped
    values would let the depth sort reorder players whose scores clearly
    differ. Spreading the ties makes the quantile function strictly increasing:
    the mapping stays order-preserving and `round()` stays unbiased."""
    out = []
    i, n = 0, len(pool)
    while i < n:
        j = i
        while j + 1 < n and pool[j + 1] == pool[i]:
            j += 1
        k = j - i + 1
        for r in range(k):
            out.append(pool[i] - 0.5 + (r + 0.5) / k)
        i = j + 1
    return out


def map_to_reference(rank_frac: float, pool: list) -> float:
    """rank fraction in (0,1) -> the reference distribution's quantile."""
    n = len(pool)
    x = rank_frac * (n - 1)
    lo = int(math.floor(x))
    hi = min(n - 1, lo + 1)
    t = x - lo
    return pool[lo] * (1.0 - t) + pool[hi] * t


def strength_index(raw: dict, scores: dict) -> dict:
    """Real-2025 team strength, the thing the template's team-to-team spread has
    to follow. 65 % record (wins + how deep the playoff run went), 35 % the
    roster's own measured production, so a loaded team that lost its season to
    injuries (KC at 6-11) does not get flattened."""
    playoff_bonus = {
        "Won Super Bowl LX": 0.085, "Lost Super Bowl LX": 0.065,
        "Lost Conference Championship": 0.048, "Lost Divisional round": 0.032,
        "Lost Wild Card round": 0.016,
    }
    rec, roster = {}, {}
    for team in raw["teams"]:
        r = team["record2025"]
        games = r["wins"] + r["losses"] + r["ties"]
        wpct = (r["wins"] + 0.5 * r["ties"]) / max(1, games)
        rec[team["abbr"]] = wpct + playoff_bonus.get(r.get("playoffResult") or "", 0.0)
        vals = sorted((scores[(team["abbr"], p["name"], p["pos"])]["quality"]
                       for p in team["players"]), reverse=True)
        roster[team["abbr"]] = statistics.mean(vals[:26])       # starters + key rotation

    def z(d):
        mu = statistics.mean(d.values())
        sd = statistics.pstdev(d.values()) or 1.0
        return {k: (v - mu) / sd for k, v in d.items()}

    zr, zq = z(rec), z(roster)
    return {k: 0.65 * zr[k] + 0.35 * zq[k] for k in zr}, rec


def calibrate(raw: dict, scores: dict, pools: dict, strength: dict, log: list):
    """Two things at once:

    1. LEVEL + SHAPE — each position's players are rank-mapped onto that
       position's reference pool, so the template reproduces the random
       generator's per-position distribution (and therefore its ~76.4 league
       mean and its starter/backup/depth tier structure) by construction.
    2. TEAM SPREAD — a per-team offset in score space is solved by fixed-point
       iteration so team mean OVR tracks real 2025 strength with a
       best-minus-worst gap of `TEAM_SPREAD_TARGET`.
    """
    # Precomputed index: per position the list of (score, key, team) and per
    # team the list of keys, so the fixed-point loop below is cheap.
    per_pos = defaultdict(list)
    per_team = defaultdict(list)
    for team in raw["teams"]:
        for p in team["players"]:
            key = (team["abbr"], p["name"], p["pos"])
            per_pos[p["pos"]].append(key)
            per_team[team["abbr"]].append(key)
    for pos in per_pos:
        per_pos[pos].sort()

    zmin = min(strength.values())
    zmax = max(strength.values())
    zspan = (zmax - zmin) or 1.0
    zmid = (zmin + zmax) / 2.0

    offsets = {t["abbr"]: 0.0 for t in raw["teams"]}
    ovr = {}
    team_mean = {}
    worst = float("inf")
    best = (float("inf"), dict(offsets))
    for it in range(600):
        for pos, keys in per_pos.items():
            pool = pools[pos]
            ranked = sorted(keys, key=lambda k: (scores[k]["score"] + offsets[k[0]], k[1]))
            n = len(ranked)
            for i, key in enumerate(ranked):
                ovr[key] = map_to_reference((i + 0.5) / n, pool)

        for abbr, keys in per_team.items():
            team_mean[abbr] = statistics.mean(ovr[k] for k in keys)
        league_mean = statistics.mean(ovr.values())
        err = {a: (league_mean + (strength[a] - zmid) / zspan * TEAM_SPREAD_TARGET)
                  - team_mean[a] for a in offsets}
        worst = max(abs(v) for v in err.values())
        if worst < best[0]:
            best = (worst, dict(offsets))
        if worst < 0.05:
            break
        # the map is discrete (a rank swap moves a whole rating point), so a
        # constant gain oscillates near the fixed point; decay it instead.
        gain = 0.45 if it < 200 else (0.20 if it < 400 else 0.08)
        for a in offsets:
            offsets[a] += gain * err[a]

    if best[0] < worst:                       # replay the best offsets found
        offsets = best[1]
        for pos, keys in per_pos.items():
            pool = pools[pos]
            ranked = sorted(keys, key=lambda k: (scores[k]["score"] + offsets[k[0]], k[1]))
            n = len(ranked)
            for i, key in enumerate(ranked):
                ovr[key] = map_to_reference((i + 0.5) / n, pool)
        for abbr, keys in per_team.items():
            team_mean[abbr] = statistics.mean(ovr[k] for k in keys)
    log.append(f"team-spread fixed point: max |team mean error| = {best[0]:.3f} OVR")

    # --- anchor the league mean on the 53-man blueprint ---------------------
    # The raw rosters carry ~56.5 players, ~3.5 more camp-depth bodies per team
    # than the 53-man blueprint, which pulls a straight composition match about
    # half a point below the generator's league mean. One global level shift
    # puts the anchor back without touching the shape or the tier structure.
    anchor = blueprint_league_mean()
    shift = anchor - statistics.mean(ovr.values())
    for k in ovr:
        ovr[k] += shift
    log.append(f"blueprint anchor {anchor:.2f} OVR; global level shift "
               f"{shift:+.2f} applied to match the random LeagueGenerator league mean")

    # --- elite tail stretch -------------------------------------------------
    vals = sorted(ovr.values())
    cut = vals[int(ELITE_STRETCH_PCTL * (len(vals) - 1))]
    top = vals[-1]
    span = max(1e-6, top - cut)
    for k, v in ovr.items():
        if v > cut:
            ovr[k] = v + ELITE_STRETCH_MAX * ((v - cut) / span) ** 1.5

    # `_smooth` already spread the reference lattice, so ordinary rounding is
    # unbiased AND order-preserving. The un-rounded values come back too: two
    # players can share an integer rating while their quality clearly differs,
    # and the depth chart must not be decided by a hash tiebreak.
    final = {k: int(max(40, min(99, round(v)))) for k, v in ovr.items()}
    return final, offsets, team_mean, dict(ovr)


# ---------------------------------------------------------------------------
# 9. Career arcs
# ---------------------------------------------------------------------------


def season_role(row: dict) -> str:
    gp, gs = row.get("gp") or 0, row.get("gs")
    share = row.get("snapShare")
    if (gs is not None and gp and gs / max(1, gp) >= 0.6) or (share is not None and share >= 0.62):
        return "starter"
    if (share is not None and share >= 0.38) or (gs is not None and gs >= 4):
        return "rotation"
    if gp >= 6 or (share is not None and share >= 0.12):
        return "backup"
    return "depth"


def career_arc(p: dict, rating: int, potential: int, tables, salt: str) -> list:
    """Real production percentile per season -> OVR band -> +-2 seeded jitter
    (ANONYMIZATION_SPEC section 3). No stat line ever leaves this function."""
    pos = p["pos"]
    seasons = p["seasons"]
    if not seasons:
        return []
    scored = []
    for row in seasons:
        s, conf = season_score(pos, row, tables)
        scored.append((row, s, conf))
    num = sum((0.62 ** max(0, SNAPSHOT_YEAR - r["year"])) * (0.4 + 0.6 * c) * s
              for r, s, c in scored)
    den = sum((0.62 ** max(0, SNAPSHOT_YEAR - r["year"])) * (0.4 + 0.6 * c)
              for r, s, c in scored) or 1.0
    career_mean = num / den

    arc = []
    for row, s, conf in scored:
        year = row["year"]
        age_then = p["age"] - (SNAPSHOT_YEAR - year)
        age_delta = 0.55 * (age_level_shift(max(20, age_then), pos)
                            - age_level_shift(p["age"], pos))
        prod_delta = max(-10.0, min(10.0, 17.0 * (s - career_mean)))
        rng = seeded("arc", salt, year)
        jitter = rng.randint(-2, 2)
        val = rating + age_delta + prod_delta + jitter
        arc.append({
            "year": year,
            "team": row.get("team"),
            "ovr": int(max(42, min(min(99, potential), round(val)))),
            "role": season_role(row),
            "gp": row.get("gp"),
            "gs": row.get("gs"),
        })
    arc.sort(key=lambda a: a["year"])
    # the most recent season must read as the player we are shipping
    if arc and arc[-1]["year"] == SNAPSHOT_YEAR:
        arc[-1]["ovr"] = int(max(rating - 3, min(rating + 3, arc[-1]["ovr"])))
    return arc


# ---------------------------------------------------------------------------
# 10. Publish-profile name generation
# ---------------------------------------------------------------------------


def _by_length(names):
    idx = defaultdict(list)
    for n in names:
        idx[len(n)].append(n)
    return idx


def _near(idx, needle, slack):
    """Every candidate whose length could be within `slack` edits of `needle`."""
    out = []
    for L in range(len(needle) - slack, len(needle) + slack + 1):
        out.extend(idx.get(L, ()))
    return out


def recombination_conflicts(firsts, lasts, block_full_norm, limit: int = 2):
    """Every `(first, last)` pair in the cross product whose CONCATENATION lands
    within `limit` edits of a real name.

    `ANONYMIZATION_SPEC.md` §1 guard 1 is a Levenshtein rule on the FULL name,
    but anything that draws a given name and a surname INDEPENDENTLY from two
    pools can reach every pair of the cross product, not only the pairs this
    tool happened to emit. Two such consumers exist:

      * `LeagueTemplateImporter.SupportStaffNamePool`, which harvests every
        `firstName` / `lastName` in the shipped template and recombines them for
        the 417 support-staff coaches it generates at runtime — where no bundle
        scan can ever see the result;
      * the app's own `RandomNameGenerator` / owner / coach pools, checked from
        `scan_bundle.py` gate E.

    Checking ~100k pairs one at a time against the blocklist costs ~4 minutes.
    This uses the concatenation identity

        d(x + y, r) = min over every split s of ( d(x, r[:s]) + d(y, r[s:]) )

    so every real name is split once and the halves are matched against the two
    pools separately: ~3 s for the same cross product.
    """
    nfirst = {f: norm_name(f) for f in firsts}
    nlast = {l: norm_name(l) for l in lasts}
    f_by_len, l_by_len = defaultdict(list), defaultdict(list)
    for f in firsts:
        f_by_len[len(nfirst[f])].append(f)
    for l in lasts:
        l_by_len[len(nlast[l])].append(l)
    if not f_by_len or not l_by_len:
        return set()
    lo_f, hi_f = min(f_by_len), max(f_by_len)
    lo_l, hi_l = min(l_by_len), max(l_by_len)

    # prefix -> every suffix a real name pairs it with, at a split point where a
    # given name could plausibly align (|split - len(first)| <= limit).
    splits = defaultdict(set)
    for r in block_full_norm:
        for s in range(max(1, lo_f - limit), min(len(r), hi_f + limit) + 1):
            rest = len(r) - s
            if rest < lo_l - limit or rest > hi_l + limit:
                continue
            splits[r[:s]].add(r[s:])

    bad = set()
    for prefix, suffixes in splits.items():
        for length in range(len(prefix) - limit, len(prefix) + limit + 1):
            for f in f_by_len.get(length, ()):
                df = levenshtein_at_most(nfirst[f], prefix, limit)
                if df > limit:
                    continue
                budget = limit - df
                for suffix in suffixes:
                    for length2 in range(len(suffix) - budget, len(suffix) + budget + 1):
                        for l in l_by_len.get(length2, ()):
                            if levenshtein_at_most(nlast[l], suffix, budget) <= budget:
                                bad.add((f, l))
    return bad


class NameFactory:
    """Fully fictional, deterministic, blocklist-clean names (spec section 1).

    Nothing here looks at the real name except to REJECT resemblance: the draw
    is independent, and the real name only feeds the seed (so rebuilds are
    stable) and the same-initials guard.
    """

    def __init__(self, blocklist: dict):
        self.stats = {"synthesized": 0, "poolRejected": 0, "attempts": 0,
                      "recombinationRejected": 0}
        self.block_full_idx = _by_length(blocklist["fullNorm"])
        self.block_last_idx = _by_length(blocklist["lastNorm"])
        self.used = set()
        # A first name that is also a real NFL SURNAME ("Bennett", "Sawyer")
        # reads as a real player's name in a roster list, so it is dropped.
        block_last_lower = {n.lower() for n in blocklist["last"]}
        self.first_pool = sorted({f for f in PUB_FIRST
                                  if f.lower() not in block_last_lower})
        self.last_pool = self._filter_last(PUB_LAST)
        if len(self.last_pool) < 250:
            raise SystemExit(
                f"surname pool too small after blocklist filter: {len(self.last_pool)}")
        # Guard 1c: the tokens this factory EMITS become a pool of their own —
        # `LeagueTemplateImporter.SupportStaffNamePool` harvests every template
        # firstName / lastName and recombines them freely. So the constraint is
        # not "the pairs I emit are clean" but "every pair the emitted tokens can
        # form is clean". `_conflicts` is the precomputed dirty set over the two
        # candidate pools; `_pool_first` / `_pool_last` are what has actually been
        # emitted so far.
        self._matrix_first = set(self.first_pool)
        self._matrix_last = set(self.last_pool)
        self._conflicts = recombination_conflicts(
            self.first_pool, self.last_pool, blocklist["fullNorm"]
        )
        self.stats["recombinationConflicts"] = len(self._conflicts)
        self._pool_first, self._pool_last = [], []
        self._pool_first_set, self._pool_last_set = set(), set()

    def _last_is_dirty(self, nl: str) -> bool:
        return any(levenshtein_at_most(nl, b, 1) <= 1
                   for b in _near(self.block_last_idx, nl, 1))

    def _full_is_dirty(self, nf: str) -> bool:
        return any(levenshtein_at_most(nf, b, 2) <= 2
                   for b in _near(self.block_full_idx, nf, 2))

    def _pair_dirty(self, first: str, last: str) -> bool:
        """Is `first + last` within 2 edits of a real name?"""
        if first in self._matrix_first and last in self._matrix_last:
            return (first, last) in self._conflicts
        # a synthesized surname is outside the precomputed matrix
        return self._full_is_dirty(norm_name(first + last))

    def _recombination_dirty(self, first: str, last: str) -> bool:
        """Would admitting these two tokens make some RECOMBINATION dirty?"""
        return (any(self._pair_dirty(first, l) for l in self._pool_last)
                or any(self._pair_dirty(f, last) for f in self._pool_first))

    def _remember(self, first: str, last: str) -> None:
        if first not in self._pool_first_set:
            self._pool_first_set.add(first)
            self._pool_first.append(first)
        if last not in self._pool_last_set:
            self._pool_last_set.add(last)
            self._pool_last.append(last)

    def _filter_last(self, pool):
        keep = []
        for s in sorted(set(pool)):
            if self._last_is_dirty(norm_name(s)):
                self.stats["poolRejected"] += 1
                continue
            keep.append(s)
        return keep

    _SYL_A = ["Bal", "Cor", "Dar", "Fen", "Gar", "Hal", "Jor", "Kel", "Lar", "Mar",
              "Nor", "Pel", "Quar", "Rav", "Sel", "Tar", "Vel", "War", "Yar", "Zel"]
    _SYL_B = ["and", "ber", "ding", "fal", "gorn", "hall", "isk", "ker", "lund",
              "mont", "nash", "pike", "quist", "ridge", "stead", "thorn", "vale",
              "wick", "yard", "zen"]

    def _synth_last(self, rng):
        return rng.choice(self._SYL_A) + rng.choice(self._SYL_B)

    def make(self, salt: str, real_name: str, team: str, pos: str) -> str:
        real_first, real_last, _ = split_name(real_name)
        real_last_head = real_last.split()[-1] if real_last else ""
        real_initials = (real_first[:1].upper(), real_last_head[:1].upper())
        for attempt in range(600):
            self.stats["attempts"] += 1
            rng = seeded("pubname", salt, real_name, team, pos, attempt)
            first = rng.choice(self.first_pool)
            if attempt < 500:
                last = rng.choice(self.last_pool)
            else:
                last = self._synth_last(rng)
            full = f"{first} {last}"
            nf, nl = norm_name(full), norm_name(last)
            if nf in self.used:
                continue
            # guard: never reuse the real first name at the same team+position
            if first.lower() == real_first.lower():
                continue
            # guard 3 (spec): same initials + same team + same position
            if (first[:1].upper(), last[:1].upper()) == real_initials:
                continue
            # guard 1a: surname must not be a real surname or a 1-edit variant
            if self._last_is_dirty(nl):
                continue
            # guard 1b: full-name Levenshtein >= 3 from every blocklisted name
            if self._full_is_dirty(nf):
                continue
            # guard 1c: and so is every RECOMBINATION these tokens enable, because
            # the importer's support-staff pool draws the halves independently
            if self._recombination_dirty(first, last):
                self.stats["recombinationRejected"] += 1
                continue
            if attempt >= 500:
                self.stats["synthesized"] += 1
            self.used.add(nf)
            self._remember(first, last)
            return full
        raise SystemExit(f"could not generate a clean publish name for {real_name}")


# ---------------------------------------------------------------------------
# 11. Bio jitter (publish profile, spec section 2)
# ---------------------------------------------------------------------------

# Publish-side jersey bands. `ANONYMIZATION_SPEC.md` section 0 does not list the
# number, but the precedent it cites (Keller / Davis v. EA) turns on exactly the
# combination "number + position + bio + stats" — a #9 quarterback in Cincinnati
# is identifiable to any fan. So the publish profile issues its own numbers from
# the position's legal NFL bands; the dev profile keeps the real ones.
JERSEY_BANDS = {
    "QB": [(1, 19)], "RB": [(20, 49)], "FB": [(20, 49)],
    "WR": [(10, 19), (80, 89)], "TE": [(40, 49), (80, 89)],
    "LT": [(50, 79)], "LG": [(50, 79)], "C": [(50, 79)],
    "RG": [(50, 79)], "RT": [(50, 79)],
    "DE": [(50, 79), (90, 99)], "DT": [(50, 79), (90, 99)],
    "OLB": [(40, 59), (90, 99)], "MLB": [(40, 59), (90, 99)],
    "CB": [(20, 39)], "FS": [(20, 39)], "SS": [(20, 39)],
    "K": [(1, 19)], "P": [(1, 19)],
}


def publish_jerseys(players, real_jerseys, abbr):
    """Deterministic, unique-per-roster, never the player's real number."""
    taken = set()
    out = {}
    for p in sorted(players, key=lambda q: (q["pos"], q["name"])):
        pool = [n for lo, hi in JERSEY_BANDS[p["pos"]] for n in range(lo, hi + 1)]
        rng = seeded("jersey", abbr, p["name"], p["pos"])
        rng.shuffle(pool)
        real = real_jerseys.get(p["name"])
        pick = next((n for n in pool if n not in taken and n != real), None)
        if pick is None:                       # band exhausted: fall back to 0-99
            pick = next(n for n in range(0, 100) if n not in taken and n != real)
        taken.add(pick)
        out[p["name"]] = pick
    return out


ROUND_BOUNDS = {1: (1, 32), 2: (33, 64), 3: (65, 105), 4: (106, 145),
                5: (146, 185), 6: (186, 225), 7: (226, 262)}

HEIGHT_RANGE = {
    "QB": (73, 77), "RB": (68, 73), "FB": (71, 74), "WR": (69, 76), "TE": (74, 78),
    "LT": (76, 80), "RT": (76, 80), "LG": (74, 78), "RG": (74, 78), "C": (73, 77),
    "DE": (74, 79), "DT": (73, 77), "OLB": (73, 77), "MLB": (72, 76), "CB": (69, 74),
    "FS": (71, 75), "SS": (71, 75), "K": (71, 75), "P": (72, 76),
}
WEIGHT_RANGE = {
    "QB": (205, 240), "RB": (195, 230), "FB": (235, 260), "WR": (175, 215),
    "TE": (235, 265), "LT": (295, 340), "RT": (295, 340), "LG": (295, 335),
    "RG": (295, 335), "C": (290, 320), "DE": (250, 285), "DT": (280, 330),
    "OLB": (230, 260), "MLB": (235, 260), "CB": (180, 205), "FS": (195, 215),
    "SS": (200, 225), "K": (185, 215), "P": (200, 225),
}


class CollegeSwapper:
    """Same-tier college replacement. Two players who really shared a school AND
    a draft class never share the replacement school either (spec section 2)."""

    def __init__(self):
        self.pools = {"P5": P5_COLLEGES, "G5": G5_COLLEGES, "FCS": FCS_COLLEGES}
        self.taken = defaultdict(set)      # (realCollege, classYear) -> {fake, ...}

    def swap(self, real: str, class_year: int, salt: str) -> str:
        tier = college_tier(real)
        pool = self.pools[tier]
        primary = primary_college(real)
        key = (primary, class_year)
        rng = seeded("college", salt, primary, class_year)
        order = pool[:]
        rng.shuffle(order)
        for cand in order:
            if cand == primary:
                continue
            if cand in self.taken[key]:
                continue
            self.taken[key].add(cand)
            return cand
        return order[0]


def jitter_bio(p: dict, salt: str, age_delta: int, swapper: CollegeSwapper,
               used_picks: dict) -> dict:
    """Returns the publish-side bio plus the list of fields actually transformed."""
    rng = seeded("bio", salt, p["name"], p["pos"])
    changed = []

    age = max(21, p["age"] + age_delta)
    if age != p["age"]:
        changed.append("age")
    years_pro = min(p["yearsPro"], max(0, age - 20))

    draft = p.get("draft")
    draft_year = draft.get("year") if draft else None
    draft_round = draft.get("round") if draft else None
    fuzzed = None
    if draft and draft.get("pick") is not None and draft_round in ROUND_BOUNDS:
        lo, hi = ROUND_BOUNDS[draft_round]
        real_pick = draft["pick"]
        # older drafts had different round sizes; never let the clamp move a
        # real slot out of its own round.
        lo, hi = min(lo, real_pick), max(hi, real_pick)
        slot_key = (draft_year, draft_round)
        for _ in range(60):
            delta = rng.randint(-8, 8)
            if delta == 0:
                continue
            cand = max(lo, min(hi, real_pick + delta))
            # a fuzzed slot must differ from the real one AND not collide with
            # another fuzzed slot in the same draft round (two "#1 overall"
            # picks in one year is the kind of artefact a reader notices).
            if cand != real_pick and cand not in used_picks[slot_key]:
                fuzzed = cand
                break
        if fuzzed is None:
            fuzzed = next((c for c in range(lo, hi + 1)
                           if c != real_pick and c not in used_picks[slot_key]),
                          lo if real_pick > lo else hi)
        used_picks[slot_key].add(fuzzed)
        changed.append("draftPick")
    elif draft and draft_round in ROUND_BOUNDS:
        lo, hi = ROUND_BOUNDS[draft_round]
        fuzzed = rng.randint(lo, hi)

    class_year = draft_year or (LEAGUE_YEAR - max(0, p["yearsPro"]))
    college = swapper.swap(p.get("college") or NO_COLLEGE, class_year, salt)
    changed.append("college")

    # body: weight always moves; height moves ~60 % of the time. Clamp to the
    # position's `PositionPhysicalProfile` band, widened where the real body
    # already sits outside it so genuine outliers are not flattened.
    hlo, hhi = HEIGHT_RANGE[p["pos"]]
    # widen by the jitter magnitude where the real body already sits outside the
    # position band, so a genuine 6-8 tackle is not clamped back to the mean.
    hlo, hhi = min(hlo, p["heightIn"] - 1), max(hhi, p["heightIn"] + 1)
    height = p["heightIn"]
    if rng.random() < 0.60:
        height = max(hlo, min(hhi, p["heightIn"] + rng.choice([-1, 1])))
        if height != p["heightIn"]:
            changed.append("heightIn")

    wlo, whi = WEIGHT_RANGE[p["pos"]]
    wlo, whi = min(wlo, p["weightLb"] - 14), max(whi, p["weightLb"] + 14)
    pct = rng.uniform(0.02, 0.04) * rng.choice([-1.0, 1.0])
    weight = int(round(p["weightLb"] * (1.0 + pct)))
    weight = max(wlo, min(whi, weight))
    if weight == p["weightLb"]:
        weight = min(whi, max(wlo, weight + (2 if weight < whi else -2)))
    if weight != p["weightLb"]:
        changed.append("weightLb")

    return {
        "age": age, "yearsPro": years_pro, "college": college,
        "draftYear": draft_year, "draftRound": draft_round,
        "draftPick": None, "fuzzedPick": fuzzed,
        "heightIn": height, "weightLb": weight,
        "_changed": changed,
    }


# ---------------------------------------------------------------------------
# 12. Face pre-assignment (docs/FACE_GENERATION_PLAN.md, phase 4)
#
# Every template person carries the face he will wear, baked here. This is not
# an optimisation: `LeagueTemplateImporter` builds `Player` / `Coach` rows with
# FRESH `UUID()`s on every import, and the runtime picker
# (`FaceLibrary.assignFace`) hashes exactly that UUID — so a template league
# that assigned its faces at runtime would show DIFFERENT portraits every time
# the same fixed league is created. Baking the ids is what makes the fixed
# league fixed all the way down to the faces.
#
# Nothing here reads an image. Buckets are a pure function of (face seed, id) —
# `tools/faces/generate_faces.py::build_spec` — so this runs correctly while the
# 2 048 pictures are still generating, and the app draws a silhouette for any
# id whose HEIC has not landed yet.
# ---------------------------------------------------------------------------

# --- generator constants, transcribed from tools/faces/generate_faces.py ----
# Keep in lockstep with that file AND with `FaceGeneratorConstants` in
# dynasty/Domain/Models/Faces/FaceCatalog.swift. The weight lists are ordered
# exactly as the Python source lists them because `face_wpick` reproduces the
# accumulation order, and float summation is order-dependent.
FACE_SEED = 20260729                 # generate_faces.py --seed
FACE_COACH_SHARE = 0.1875            # generate_faces.py --coach-share
FACE_GENERATED_POOL = 2048           # ids face_00000..face_02047 (--count 2048)
FACE_RESERVE_POOL = 512              # ids face_02048..face_02559 (--count 2560)
FACE_FEMALE_POOL = 1024              # ids face_02560..face_03583 (--count 3584)
FACE_POOL = FACE_GENERATED_POOL + FACE_RESERVE_POOL + FACE_FEMALE_POOL
# The extended range is where female coach faces live. It is NOT a second
# reserve: FACE_RESERVE_POOL keeps naming only the 512-id band the template
# draws its overflow from, and the runtime picker treats 2560+ as a first-class
# generated area. Here in the transform the distinction costs nothing —
# `_face_take` and gate 19's suffix rule ask only "is this id >=
# FACE_GENERATED_POOL", and ids go out lowest-first, so the female ids just
# extend the same tail (the template stops at face_02344 and never reaches it).
FACE_FEMALE_RANGE_START = 2560       # generate_faces.py FEMALE_RANGE_START
FACE_FEMALE_COACH_SHARE = 0.22       # generate_faces.py --female-coach-share

FACE_TONES = [("black", 0.55), ("white", 0.28), ("latino", 0.07),
              ("pacific", 0.04), ("mixed", 0.06)]
FACE_PLAYER_AGES = [("20-24", 0.38), ("25-29", 0.40), ("30-36", 0.22)]
FACE_COACH_AGES = [("38-50", 0.45), ("50-68", 0.55)]
FACE_PLAYER_BUILDS = [("lean", 0.30), ("athletic", 0.50), ("heavy", 0.20)]
FACE_COACH_BUILDS = [("lean", 0.4), ("athletic", 0.35), ("heavy", 0.25)]

# Ordered lean -> athletic -> heavy so "the next-closest build" is just a step
# along the list (used when a bucket runs out).
FACE_BUILD_ORDER = ["lean", "athletic", "heavy"]
FACE_AGE_ORDER = {"player": ["20-24", "25-29", "30-36"],
                  "coach": ["38-50", "50-68"]}
# Band mid-points, for "which band is the least-wrong substitute".
FACE_AGE_CENTER = {"20-24": 22.0, "25-29": 27.0, "30-36": 33.0,
                   "38-50": 44.0, "50-68": 59.0}

# Position group -> build weights. Mirrors `FaceLibrary.playerBuildWeights`.
FACE_POSITION_BUILDS = {
    "LT": [("heavy", 0.78), ("athletic", 0.20), ("lean", 0.02)],
    "LG": [("heavy", 0.78), ("athletic", 0.20), ("lean", 0.02)],
    "C":  [("heavy", 0.78), ("athletic", 0.20), ("lean", 0.02)],
    "RG": [("heavy", 0.78), ("athletic", 0.20), ("lean", 0.02)],
    "RT": [("heavy", 0.78), ("athletic", 0.20), ("lean", 0.02)],
    "DT": [("heavy", 0.78), ("athletic", 0.20), ("lean", 0.02)],
    "DE": [("heavy", 0.40), ("athletic", 0.55), ("lean", 0.05)],
    "FB": [("heavy", 0.40), ("athletic", 0.55), ("lean", 0.05)],
    "TE": [("heavy", 0.22), ("athletic", 0.68), ("lean", 0.10)],
    "MLB": [("heavy", 0.22), ("athletic", 0.68), ("lean", 0.10)],
    "OLB": [("heavy", 0.10), ("athletic", 0.72), ("lean", 0.18)],
    "SS": [("heavy", 0.10), ("athletic", 0.72), ("lean", 0.18)],
    "QB": [("heavy", 0.04), ("athletic", 0.66), ("lean", 0.30)],
    "RB": [("heavy", 0.04), ("athletic", 0.66), ("lean", 0.30)],
    "FS": [("heavy", 0.04), ("athletic", 0.66), ("lean", 0.30)],
    "WR": [("heavy", 0.01), ("athletic", 0.39), ("lean", 0.60)],
    "CB": [("heavy", 0.01), ("athletic", 0.39), ("lean", 0.60)],
    "K":  [("heavy", 0.08), ("athletic", 0.42), ("lean", 0.50)],
    "P":  [("heavy", 0.08), ("athletic", 0.42), ("lean", 0.50)],
}

# Assignment priority: the most visible people pick first, so the ids whose
# pictures may not exist yet (the reserve range) land on the least visible.
FACE_ROLE_PRIORITY = {"starter": 0, "rotation": 1, "backup": 2, "depth": 3}

FACE_COACH_SLOT_ROLE = {"hc": "HeadCoach",
                        "oc": "OffensiveCoordinator",
                        "dc": "DefensiveCoordinator"}

# Gate-19 floors. Neither can be 100 %: the league wants 970 faces in the
# 25-29 band where the GENERATED range holds 656, and 519 `heavy` faces where
# it holds 339, so some people MUST take a neighbouring bucket (see the pool
# arithmetic in TRANSFORM_QA §8). The whole 3 584-id pool does now hold enough
# of both (1 138 / 576), but `_face_draw` walks the entire ladder inside the
# generated range before it touches an id at 2048+, so it is the generated
# range's arithmetic that binds. The floors sit a few points under the measured
# values (band 82-84 %, build 89 %), i.e. they catch a regression in the
# ladder, not the arithmetic.
FACE_BAND_MATCH_MIN = 78.0
FACE_BUILD_MATCH_MIN = 82.0


def face_wpick(rng, items):
    """`generate_faces.py::wpick`, restricted to (tag, weight) pairs."""
    r, acc = rng.random() * sum(w for _, w in items), 0.0
    for tag, w in items:
        acc += w
        if r <= acc:
            return tag
    return items[-1][0]


def face_bucket(index: int) -> dict:
    """The bucket `generate_faces.py` gives `face_<index>` — images not needed.

    Reproduces `build_spec`'s draw order exactly (role, [gender], tone, ageBand,
    build); each pick consumes one `random()`. Verified against the live
    generator manifest by gate 19.

    Two things are gated on the id, not on the pool size: ids at/after
    FACE_FEMALE_RANGE_START spend ONE extra `random()` on the gender of a coach
    face (players skip the draw but still carry "male"), and only those ids
    carry a `gender` key at all. Ids below it predate the female range and must
    stay byte-identical to the 2 560 manifest entries already shipped — adding
    the key there would fail gate 19 from the other side.
    """
    rng = random.Random(f"{FACE_SEED}:{face_id(index)}")
    role = "coach" if rng.random() < FACE_COACH_SHARE else "player"
    gender = "male"
    if index >= FACE_FEMALE_RANGE_START and role == "coach":
        gender = "female" if rng.random() < FACE_FEMALE_COACH_SHARE else "male"
    tone = face_wpick(rng, FACE_TONES)
    age = face_wpick(rng, FACE_COACH_AGES if role == "coach" else FACE_PLAYER_AGES)
    build = face_wpick(rng, FACE_PLAYER_BUILDS if role == "player" else FACE_COACH_BUILDS)
    if index >= FACE_FEMALE_RANGE_START:
        return {"role": role, "gender": gender, "ageBand": age,
                "tone": tone, "build": build}
    return {"role": role, "ageBand": age, "tone": tone, "build": build}


def face_id(index: int) -> str:
    return "face_%05d" % index


_FACE_POOL_CACHE = None


def face_pool():
    """`[bucket]` for the whole extended pool, built once."""
    global _FACE_POOL_CACHE
    if _FACE_POOL_CACHE is None:
        _FACE_POOL_CACHE = [face_bucket(i) for i in range(FACE_POOL)]
    return _FACE_POOL_CACHE


def face_player_band(age: int) -> str:
    """`FaceLibrary.ageBand(role: .player,)` — ages outside the generated
    range clamp to the nearest band."""
    if age <= 24:
        return "20-24"
    if age <= 29:
        return "25-29"
    return "30-36"


def face_coach_band(age: int) -> str:
    return "38-50" if age <= 50 else "50-68"


# --- the importer's coach age, predicted -----------------------------------
# A template coach has no age in the file: `LeagueTemplateImporter.makeStaff`
# lets `LeagueGenerator.generateCoach` draw it from a seeded stream. To give
# him an age-appropriate face we replay that ONE draw here.
#
# COUPLING (guarded by a comment at both ends): the age is the FIRST value the
# coach's stream yields, because `nameOverride` short-circuits the two name
# draws for exactly the hc/oc/dc slots the template names. Insert an RNG draw
# ahead of `let age = ...` in `generateCoach` and template coach faces start
# picking the wrong age band (a soft failure — gate 19 reports the band-match
# share, which would drop to ~50 %).
_U64 = (1 << 64) - 1


def swift_fnv1a(text: str) -> int:
    """`LeagueTemplateImporter.fnv1a`. NB: the multiplier is the app's literal
    `0x1000_0000_01B3`, which is one hex digit longer than the canonical FNV-1a
    prime — mirroring the app is the point, not the textbook."""
    h = 0xCBF29CE484222325
    for b in text.encode("utf-8"):
        h ^= b
        h = (h * 0x1000000001B3) & _U64
    return h


class SwiftSplitMix64:
    """`SeededLeagueRandom` (TemplateAttributeSolver.swift) — SplitMix64."""

    def __init__(self, seed: int):
        self.state = seed & _U64

    def next(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & _U64
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & _U64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & _U64
        return (z ^ (z >> 31)) & _U64


def swift_random_closed(rng: SwiftSplitMix64, lo: int, hi: int) -> int:
    """`Int.random(in: lo...hi, using:)` on a 64-bit target — Swift's stdlib
    uses Lemire's multiply-shift there, NOT modulo rejection (that branch is
    32-bit only), so the arithmetic below is the one the app actually runs."""
    delta = (hi - lo) & _U64
    if delta == _U64:
        return rng.next()
    delta += 1
    r = rng.next()
    m = r * delta
    low, high = m & _U64, m >> 64
    if low < delta:
        threshold = ((1 << 64) - delta) % delta
        while low < threshold:
            r = rng.next()
            m = r * delta
            low, high = m & _U64, m >> 64
    return lo + high


def template_coach_age(team_key: str, slot: str) -> int:
    """The age `generateCoach` will hand this template staff slot."""
    seed = (GLOBAL_SEED + swift_fnv1a(f"{team_key}|{FACE_COACH_SLOT_ROLE[slot]}")) & _U64
    return swift_random_closed(SwiftSplitMix64(seed), 35, 68)


# --- allocation -------------------------------------------------------------


def _face_ladder(role: str, band: str, build: str):
    """Candidate buckets, best first.

    Build is relaxed BEFORE age, matching `FaceLibrary.pickLocked`'s tier order
    (exact bucket -> same age band, any build -> any face of the role): a
    22-year-old rookie wearing a 60-year-old's face is a bug the user sees
    instantly, a slightly-wrong body type is not.
    """
    def builds_from(b):
        i = FACE_BUILD_ORDER.index(b)
        return sorted(FACE_BUILD_ORDER, key=lambda x: (abs(FACE_BUILD_ORDER.index(x) - i),
                                                       FACE_BUILD_ORDER.index(x)))

    def bands_from(a):
        centre = FACE_AGE_CENTER[a]
        return sorted(FACE_AGE_ORDER[role],
                      key=lambda x: (abs(FACE_AGE_CENTER[x] - centre), FACE_AGE_CENTER[x]))

    keys = [(role, band, b) for b in builds_from(build)]
    for other in bands_from(band)[1:]:
        keys.extend((role, other, b) for b in builds_from(build))
    return keys


def _face_take(avail, keys, allow_reserve: bool):
    """Lowest free id along `keys`, optionally allowed into the reserve range.

    Lowest-id-first is deliberate: `generate_faces.py` works through the ids in
    order, so the people who pick first are also the people whose pictures
    exist first while the library is still generating.
    """
    for key in keys:
        bucket = avail.get(key)
        if not bucket:
            continue
        index = bucket[0]
        # The deque is ascending, so a reserve id at the head means this bucket
        # has nothing left in the generated range.
        if index >= FACE_GENERATED_POOL and not allow_reserve:
            continue
        bucket.popleft()
        return index
    return None


def _face_draw(avail, role: str, band: str, build: str):
    """One face for one person: whole ladder inside the generated range first,
    only then the same ladder inside the reserve range."""
    keys = _face_ladder(role, band, build)
    index = _face_take(avail, keys, allow_reserve=False)
    if index is None:
        index = _face_take(avail, keys, allow_reserve=True)
    return index


def assign_faces(doc: dict) -> dict:
    """Writes `faceID` onto every player and every named coach of `doc`.

    Returns the report gate 19 and TRANSFORM_QA read. Assignment is per
    profile: the publish profile's ages are jittered ±1, so a player who sits
    on a band boundary is allowed a different (age-correct) face there.
    """
    pool = face_pool()
    avail = defaultdict(deque)
    for i, bucket in enumerate(pool):
        avail[(bucket["role"], bucket["ageBand"], bucket["build"])].append(i)

    # --- demand, in "who is most visible" order ---------------------------
    people = []                     # (sort key, kind, want, setter)
    for team in doc["teams"]:
        abbr = team["identity"]["key"]
        for p in team["players"]:
            want = (
                "player",
                face_player_band(p["age"]),
                face_wpick(seeded("faceBuild", p["id"]), FACE_POSITION_BUILDS[p["pos"]]),
            )
            people.append(((FACE_ROLE_PRIORITY.get(p["role"], 3), -p["ratingTarget"], p["id"]),
                           "player", want, p, abbr))
        for slot in ("hc", "oc", "dc"):
            member = team["staff"].get(slot)
            if not member:
                continue
            age = template_coach_age(abbr, slot)
            want = (
                "coach",
                face_coach_band(age),
                face_wpick(seeded("faceBuild", "coach", abbr, slot), FACE_COACH_BUILDS),
            )
            # Coaches draw from a disjoint half of the pool, so their position
            # in this order only has to be stable, not meaningful.
            people.append(((-1, 0, f"{abbr}|{slot}"), "coach", want, member, abbr))
    people.sort(key=lambda row: row[0])

    report = {
        "assigned": 0, "players": 0, "coaches": 0, "unassigned": [],
        "reserve": [], "exactBucket": 0, "bandMatch": 0, "buildMatch": 0,
        "roleMismatch": 0, "order": {},
    }
    for rank, (_key, kind, want, target, abbr) in enumerate(people):
        role, band, build = want
        index = _face_draw(avail, role, band, build)
        if index is None:
            target["faceID"] = None
            report["unassigned"].append(f"{abbr}/{target.get('name')}")
            continue
        got = pool[index]
        target["faceID"] = face_id(index)
        report["order"][face_id(index)] = rank
        report["assigned"] += 1
        report["players" if kind == "player" else "coaches"] += 1
        report["roleMismatch"] += int(got["role"] != role)
        report["bandMatch"] += int(got["ageBand"] == band)
        report["buildMatch"] += int(got["build"] == build)
        report["exactBucket"] += int(got["ageBand"] == band and got["build"] == build)
        if index >= FACE_GENERATED_POOL:
            report["reserve"].append((rank, kind, target.get("role"), face_id(index)))
    report["freeGenerated"] = sum(
        1 for key, ids in avail.items() for i in ids if i < FACE_GENERATED_POOL
    )
    report["freeReserve"] = sum(
        1 for key, ids in avail.items() for i in ids if i >= FACE_GENERATED_POOL
    )
    return report


# ---------------------------------------------------------------------------
# 13. Assembly
# ---------------------------------------------------------------------------


def strip_trade_note(note):
    """Keep the factual ownership chain, drop the prose (which names players)."""
    if not note:
        return None
    head = note.split(":")[0].strip()
    if head.lower().startswith("uncertain"):
        return "compensatory (awarded March 2026)"
    head = re.sub(r"\s*\([^)]*\)\s*$", "", head).strip()
    return head or "via trade"


def resolve_jerseys(team_players: list, ratings: dict, abbr: str, report: list):
    """QA_REPORT carry-in 2: BUF #23 and IND #17 are real in-season re-issues.
    The higher-rated man keeps the number; the other gets the lowest free one."""
    used = defaultdict(list)
    for p in team_players:
        used[p["jersey"]].append(p)
    assigned = {}
    taken = set()
    for num, plist in sorted(used.items()):
        if len(plist) == 1:
            assigned[plist[0]["name"]] = num
            taken.add(num)
            continue
        ordered = sorted(plist, key=lambda q: -ratings[(abbr, q["name"], q["pos"])])
        assigned[ordered[0]["name"]] = num
        taken.add(num)
        for loser in ordered[1:]:
            for cand in list(range(1, 100)):
                if cand not in taken and cand not in used:
                    assigned[loser["name"]] = cand
                    taken.add(cand)
                    report.append(
                        f"jersey collision {abbr} #{num}: kept by the higher-rated "
                        f"player; {loser['name']} reassigned to #{cand}")
                    break
    return assigned


def dev_statlines(p: dict) -> list:
    """devProfile only — exact stat lines are allowed here (never in publish)."""
    out = []
    for row in p["seasons"]:
        entry = {
            "year": row["year"], "team": row.get("team"),
            "gp": row.get("gp"), "gs": row.get("gs"),
            "snapShare": row.get("snapShare"),
            "stats": dict(row.get("stats") or {}),
        }
        if row.get("post"):
            entry["post"] = {"gp": row["post"].get("gp"),
                             "stats": dict(row["post"].get("stats") or {})}
        out.append(entry)
    return out


def build_templates(raw: dict, log: list):
    tables = percentile_tables(raw)
    scores = derive_scores(raw, tables)
    depth_fixes = apply_depth_corrections(raw, scores, log)
    pools = build_reference_pools(raw)
    strength, records = strength_index(raw, scores)
    ratings, offsets, team_mean, ovr_float = calibrate(raw, scores, pools, strength, log)

    blocklist = build_blocklist(raw)
    factory = NameFactory(blocklist)
    swapper = CollegeSwapper()
    used_picks = defaultdict(set)          # (draftYear, round) -> fuzzed slots

    # Balanced age jitter: exactly half the league goes -1, half +1, ordered by
    # a stable hash so the age pyramid is preserved (spec section 2).
    all_players = [(t["abbr"], p) for t in raw["teams"] for p in t["players"]]
    order = sorted(all_players,
                   key=lambda ap: stable_id("agejitter", ap[0], ap[1]["name"]))
    age_delta = {}
    for i, (abbr, p) in enumerate(order):
        age_delta[(abbr, p["name"])] = -1 if i % 2 == 0 else 1

    staffs = raw["staffs"]["staffs"]
    picks = raw["draft"]["picks"]

    dev_teams, pub_teams = [], []
    jersey_report = []
    transform_counts = {}

    for team in raw["teams"]:
        abbr = team["abbr"]
        jerseys = resolve_jerseys(team["players"], ratings, abbr, jersey_report)
        pub_jerseys = publish_jerseys(team["players"], jerseys, abbr)

        staff = staffs.get(abbr, {})
        dev_staff, pub_staff = {}, {}
        for slot, key in (("hc", "headCoach"), ("oc", "offensiveCoordinator"),
                          ("dc", "defensiveCoordinator")):
            s = staff.get(key)
            if not s:
                dev_staff[slot] = None
                pub_staff[slot] = None
                continue
            real = s["name"]
            since = s.get("sinceYear")
            crng = seeded("coach", abbr, slot, real)
            # `sinceYear` ±1 (spec §4) — the DIRECTION is chosen among the moves
            # that survive the [1990, LEAGUE_YEAR] clamp, never clamped after the
            # fact. Drawing first and clamping second silently returned the real
            # value for every 2026 hire (a +1 on 2026 clamps back to 2026), which
            # shipped 30 of 95 coaches' exact real tenure.
            pub_since = None
            if since:
                moves = [d for d in (-1, 1) if 1990 <= since + d <= LEAGUE_YEAR]
                pub_since = since + crng.choice(moves) if moves else since
            dev_staff[slot] = {
                "name": dev_morph(real, f"coach|{abbr}|{slot}"),
                "sinceYear": since,
                "background": s.get("background") or ("offense" if slot == "oc" else
                                                      "defense" if slot == "dc" else None),
            }
            pub_staff[slot] = {
                "name": factory.make(f"coach|{abbr}|{slot}", real, abbr, slot.upper()),
                "sinceYear": pub_since,
                "background": dev_staff[slot]["background"],
            }
        for holder in (dev_staff, pub_staff):
            holder["offScheme"] = staff.get("offScheme")
            holder["defScheme"] = staff.get("defScheme")

        team_picks = []
        for pk in picks.get(abbr, []):
            team_picks.append({
                "round": pk["round"],
                "overallPick": pk["overallPick"],
                "originalTeam": pk["originalTeam"],
                "pickType": pk["pickType"],
                "via": strip_trade_note(pk.get("viaTradeNote")),
            })

        float_of = {stable_id("player", abbr, p["name"], p["pos"]):
                    ovr_float[(abbr, p["name"], p["pos"])] for p in team["players"]}
        dev_players, pub_players = [], []
        for p in team["players"]:
            pos = p["pos"]
            key = (abbr, p["name"], pos)
            rating = ratings[key]
            salt = f"{abbr}|{p['name']}|{pos}"
            prng = seeded("potential", salt)
            potential = veteran_potential(prng, rating, p["age"], pos)
            rates = aggregate_career_rates(pos, p["seasons"])
            hints = area_hints(pos, rates, p["heightIn"], p["weightLb"])
            arc = career_arc(p, rating, potential, tables, salt)
            jersey = jerseys[p["name"]]
            # one school, not the transfer chain — the game shows a single
            # college, and the head of the chain is the school of record.
            college_dev = primary_college(p.get("college"))
            pid = stable_id("player", abbr, p["name"], pos)
            udfa = not p.get("draft")
            # DEV-ONLY. `notes` carries individual-level real facts — most of all
            # `injuredAtSeasonEnd`, a real medical event for a named person.
            # `ANONYMIZATION_SPEC.md` §3 ships "only a coarse durability hint …
            # no real injury timeline", and §0 keeps team + position + depth rank
            # by design, so "the Kansas City QB1 who finished 2025 on IR" would be
            # a single-player identification out of the shipped bundle alone.
            # The publish row therefore carries `notes: null` (gate 15), and
            # nothing in the app reads the field anyway.
            notes = []
            if udfa:
                notes.append("undrafted")
            if p.get("injuredAtSeasonEnd"):
                notes.append("finished 2025 on injured reserve")

            dev_name = dev_morph(p["name"], f"player|{abbr}")
            dfirst, dlast, dsuf = split_name(dev_name)
            dev_players.append({
                "id": pid, "name": dev_name,
                "firstName": dfirst, "lastName": (dlast + (" " + dsuf if dsuf else "")).strip(),
                "pos": pos, "jersey": jersey,
                "age": p["age"], "yearsPro": p["yearsPro"],
                "college": college_dev,
                "draftYear": (p["draft"] or {}).get("year") if p.get("draft") else None,
                "draftRound": (p["draft"] or {}).get("round") if p.get("draft") else None,
                "draftPick": (p["draft"] or {}).get("pick") if p.get("draft") else None,
                "fuzzedPick": None,
                "heightIn": p["heightIn"], "weightLb": p["weightLb"],
                "ratingTarget": rating, "areaHints": hints, "potential": potential,
                "roleHint": p.get("role"), "depthRankHint": p.get("depthChartRank"),
                "careerArc": arc,
                "statLines": dev_statlines(p),
                "notes": notes or None,
            })

            bio = jitter_bio(p, salt, age_delta[(abbr, p["name"])], swapper, used_picks)
            pub_name = factory.make(f"player|{abbr}", p["name"], abbr, pos)
            pfirst, plast, _ = split_name(pub_name)
            transformed = ["name", "jersey"] + bio["_changed"]
            transform_counts[pid] = transformed
            pub_arc = [{"year": a["year"], "team": a["team"], "ovr": a["ovr"],
                        "role": a["role"], "gp": None, "gs": None} for a in arc]
            pub_players.append({
                "id": pid, "name": pub_name,
                "firstName": pfirst, "lastName": plast,
                "pos": pos, "jersey": pub_jerseys[p["name"]],
                "age": bio["age"], "yearsPro": bio["yearsPro"],
                "college": bio["college"],
                "draftYear": bio["draftYear"], "draftRound": bio["draftRound"],
                "draftPick": None, "fuzzedPick": bio["fuzzedPick"],
                "heightIn": bio["heightIn"], "weightLb": bio["weightLb"],
                "ratingTarget": rating, "areaHints": hints, "potential": potential,
                "roleHint": p.get("role"), "depthRankHint": p.get("depthChartRank"),
                "careerArc": pub_arc,
                "statLines": None,
                # never `notes` — see the comment where `notes` is built.
                "notes": None,
            })

        # Depth order is re-derived from the ratings for BOTH profiles, so the
        # importer never has to trust the raw one-season volume ranking.
        for plist in (dev_players, pub_players):
            by_pos = defaultdict(list)
            for pl in plist:
                by_pos[pl["pos"]].append(pl)
            for pos, group in by_pos.items():
                group.sort(key=lambda q: (-float_of[q["id"]], q["id"]))
                quota = STARTER_QUOTA_HINT.get(pos, 1)
                for i, pl in enumerate(group):
                    pl["depthRank"] = i + 1
                    # Mirrors the generator's per-position depth index: the top
                    # `quota` are the starting unit, the next `quota` are the
                    # rotation/second unit, the rest is depth.
                    if i < quota:
                        pl["role"] = "starter"
                    elif quota >= 2 and i < quota + max(1, quota - 1):
                        pl["role"] = "rotation"
                    elif i < 2 * quota + 1:
                        pl["role"] = "backup"
                    else:
                        pl["role"] = "depth"
            plist.sort(key=lambda q: (POSITIONS.index(q["pos"]), q["depthRank"]))

        common = {
            "record2025": dict(team["record2025"]),
            "conference": team["conference"],
            "division": team["division"],
            "baseDefense": team.get("baseDefense"),
            "picks2026": team_picks,
        }
        dev_teams.append({
            "identity": {
                "key": abbr, "appAbbr": APP_ABBR[abbr], "city": CITY_OF[abbr],
                "nickname": DEV_NICKNAMES[abbr],
                "fullName": f"{CITY_OF[abbr]} {DEV_NICKNAMES[abbr]}",
            },
            **common, "staff": dev_staff, "players": dev_players,
        })
        pub_teams.append({
            "identity": {
                "key": abbr, "appAbbr": APP_ABBR[abbr], "city": CITY_OF[abbr],
                "nickname": PUBLISH_NICKNAMES[abbr],
                "fullName": f"{CITY_OF[abbr]} {PUBLISH_NICKNAMES[abbr]}",
            },
            **common, "staff": pub_staff, "players": pub_players,
        })

    log.extend(jersey_report)

    meta = {
        "schemaVersion": SCHEMA_VERSION,
        "globalSeed": GLOBAL_SEED,
        # Deliberately NOT wall-clock: the whole point of a fixed template is
        # that a rebuild is byte-identical, so the stamp is the source
        # snapshot's own date. The build time is recorded in TRANSFORM_QA.md.
        "generated": raw.get("generated"),
        "leagueYear": LEAGUE_YEAR,
        "source": {
            "raw": "tools/league-data/raw/league_raw_2026.json",
            "rawSchemaVersion": raw.get("schemaVersion"),
            "snapshotDate": raw["draft"].get("snapshotDate"),
        },
        "divisions": raw["divisions"],
        "draftOrder2026": raw["draft"]["draftOrder2026"],
        "calibration": {
            "decision": "Match the random LeagueGenerator level and spread "
                        "(league mean OVR ~76.4, its starter/backup/depth tier "
                        "structure). NOT the DEVELOPMENT_NFL_REFERENCE section-8 "
                        "absolute bands — that is a separate deferred wave.",
            "referenceSimReps": REF_SIM_REPS,
            "teamSpreadTarget": TEAM_SPREAD_TARGET,
            "teamOffsets": {k: round(v, 3) for k, v in offsets.items()},
        },
    }

    dev = dict(meta, profile="dev", teams=dev_teams)
    pub = dict(meta, profile="publish", teams=pub_teams)

    # Phase-4 faces: baked LAST, because the allocation order is "most visible
    # first" and visibility is `role` + `ratingTarget`, both of which are only
    # final once the depth chart above has been re-derived.
    faces = {"dev": assign_faces(dev), "publish": assign_faces(pub)}
    log.append(
        f"faces: {faces['publish']['assigned']} pre-assigned per profile "
        f"({faces['publish']['players']} players + {faces['publish']['coaches']} coaches), "
        f"{len(faces['publish']['reserve'])} from the reserve range "
        f"(face_{FACE_GENERATED_POOL:05d}+), {faces['publish']['freeGenerated']} "
        f"generated-range faces left for the career"
    )

    return dev, pub, {
        "ratings": ratings, "blocklist": blocklist, "factory": factory,
        "transform_counts": transform_counts, "depth_fixes": depth_fixes,
        "team_mean": team_mean, "records": records, "raw": raw,
        "faces": faces,
    }


# ---------------------------------------------------------------------------
# 14. QA gates
# ---------------------------------------------------------------------------

REQUIRED_PLAYER_KEYS = {
    "id", "name", "firstName", "lastName", "pos", "jersey", "age", "yearsPro",
    "college", "draftYear", "draftRound", "draftPick", "fuzzedPick", "heightIn",
    "weightLb", "ratingTarget", "areaHints", "potential", "roleHint",
    "depthRankHint", "role", "depthRank", "careerArc", "statLines", "notes",
    "faceID",
}
REQUIRED_TEAM_KEYS = {"identity", "record2025", "conference", "division",
                      "baseDefense", "picks2026", "staff", "players"}


def gate(results, name, ok, detail):
    results.append({"gate": name, "pass": bool(ok), "detail": detail})
    return bool(ok)


def spearman(xs, ys):
    def rank(v):
        order = sorted(range(len(v)), key=lambda i: v[i])
        r = [0.0] * len(v)
        i = 0
        while i < len(order):
            j = i
            while j + 1 < len(order) and v[order[j + 1]] == v[order[i]]:
                j += 1
            avg = (i + j) / 2.0 + 1
            for k in range(i, j + 1):
                r[order[k]] = avg
            i = j + 1
        return r
    rx, ry = rank(xs), rank(ys)
    mx, my = statistics.mean(rx), statistics.mean(ry)
    num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    den = math.sqrt(sum((a - mx) ** 2 for a in rx) * sum((b - my) ** 2 for b in ry))
    return num / den if den else 0.0


def run_gates(dev, pub, ctx, log):
    res = []
    blocklist = ctx["blocklist"]
    raw = ctx["raw"]

    # ---- G1 schema ---------------------------------------------------------
    schema_err = []
    for label, doc in (("dev", dev), ("publish", pub)):
        if doc["schemaVersion"] != SCHEMA_VERSION or doc["globalSeed"] != GLOBAL_SEED:
            schema_err.append(f"{label}: bad header")
        if len(doc["teams"]) != 32:
            schema_err.append(f"{label}: {len(doc['teams'])} teams")
        for t in doc["teams"]:
            if set(t.keys()) != REQUIRED_TEAM_KEYS:
                schema_err.append(f"{label}/{t['identity']['key']}: team keys "
                                  f"{sorted(set(t.keys()) ^ REQUIRED_TEAM_KEYS)}")
                break
            for p in t["players"]:
                if set(p.keys()) != REQUIRED_PLAYER_KEYS:
                    schema_err.append(f"{label}/{t['identity']['key']}/{p['name']}: player keys "
                                      f"{sorted(set(p.keys()) ^ REQUIRED_PLAYER_KEYS)}")
                    break
                if not (40 <= p["ratingTarget"] <= 99) or not (p["potential"] >= p["ratingTarget"]):
                    schema_err.append(f"{label}/{p['name']}: rating/potential out of range")
                    break
                if p["college"] in (None, ""):
                    schema_err.append(f"{label}/{p['name']}: null college")
                    break
    dev_keys = {k for k in dev if k != "teams"}
    pub_keys = {k for k in pub if k != "teams"}
    if dev_keys != pub_keys:
        schema_err.append(f"header key mismatch: {sorted(dev_keys ^ pub_keys)}")
    gate(res, "schema-validate", not schema_err,
         "dev + publish share one schema; 32 teams; ratings 40-99; potential >= rating; "
         "no null colleges" if not schema_err else "; ".join(schema_err[:5]))

    # ---- G2 blocklist / Levenshtein ---------------------------------------
    pub_names = []
    for t in pub["teams"]:
        for p in t["players"]:
            pub_names.append((p["name"], t["identity"]["key"], p["pos"]))
        for slot in ("hc", "oc", "dc"):
            s = t["staff"].get(slot)
            if s:
                pub_names.append((s["name"], t["identity"]["key"], slot))
    viol = []
    for name, team, pos in pub_names:
        n = norm_name(name)
        for b in blocklist["fullNorm"]:
            if abs(len(b) - len(n)) > 2:
                continue
            d = levenshtein_at_most(n, b, 2)
            if d <= 2:
                viol.append(f"{name} ({team}/{pos}) is Levenshtein {d} from a real name")
                break
    gate(res, "publish-name-levenshtein>=3", not viol,
         f"{len(pub_names)} generated publish names checked against a "
         f"{len(blocklist['fullNorm'])}-name blocklist; minimum distance >= 3"
         if not viol else "; ".join(viol[:5]))

    # ---- G3 raw-name substring scan of the publish identity surface -------
    # Scanning the whole document would false-positive on facts that are not
    # identities (the city "Houston", the college "Howard"), so the scan is
    # aimed at exactly the fields that carry a person: player and coach names,
    # team nicknames, and the pick trade notes.
    surface = []
    for t in pub["teams"]:
        surface.append(t["identity"]["nickname"])   # cities are kept facts, so
        # `fullName` (which carries the real city) is deliberately not scanned.
        for p in t["players"]:
            surface.extend([p["name"], p["firstName"], p["lastName"]])
        for slot in ("hc", "oc", "dc"):
            s = t["staff"].get(slot)
            if s:
                surface.append(s["name"])
        for pk in t["picks2026"]:
            if pk.get("via"):
                surface.append(pk["via"])
    blob = " | ".join(surface)
    hits = []
    for real in blocklist["full"]:
        if real in blob:
            hits.append(real)
    for ln in blocklist["last"]:
        if len(ln) >= 4 and re.search(r"\b" + re.escape(ln) + r"\b", blob):
            hits.append(ln)
    gate(res, "publish-no-real-name-substring", not hits,
         f"{len(surface)} identity-bearing strings (player + coach names, team "
         "nicknames, pick trade notes) scanned: no real full name and no real "
         "surname (>=4 chars) appears in any of them"
         if not hits else f"{len(hits)} hits: {hits[:8]}")

    # ---- G4 duplicate generated names -------------------------------------
    seen = defaultdict(int)
    for name, _, _ in pub_names:
        seen[name] += 1
    dups = [k for k, v in seen.items() if v > 1]
    gate(res, "publish-names-unique", not dups,
         f"{len(pub_names)} names, all distinct" if not dups else f"duplicates: {dups[:6]}")

    # ---- G5 same-initials + team + position guard -------------------------
    real_index = {}
    for t in raw["teams"]:
        for p in t["players"]:
            f, l, _ = split_name(p["name"])
            real_index[(t["abbr"], p["pos"], stable_id("player", t["abbr"], p["name"], p["pos"]))] = \
                (f[:1].upper(), l.split()[-1][:1].upper() if l else "")
    init_viol = []
    for t in pub["teams"]:
        for p in t["players"]:
            k = (t["identity"]["key"], p["pos"], p["id"])
            if k in real_index:
                gen = (p["firstName"][:1].upper(), p["lastName"].split()[-1][:1].upper())
                if gen == real_index[k]:
                    init_viol.append(f"{p['name']} @ {t['identity']['key']} {p['pos']}")
    gate(res, "publish-no-same-initials", not init_viol,
         "no publish player shares initials with his real counterpart at the same "
         "team + position" if not init_viol else f"{len(init_viol)}: {init_viol[:5]}")

    # ---- G6 bio transform coverage ----------------------------------------
    thin = []
    for t in pub["teams"]:
        for p in t["players"]:
            fields = ctx["transform_counts"].get(p["id"], [])
            if len(set(fields)) < 3:
                thin.append(f"{p['name']} ({len(set(fields))}: {sorted(set(fields))})")
    counts = [len(set(ctx["transform_counts"][pid])) for pid in ctx["transform_counts"]]
    gate(res, "publish-bio-jitter>=3-fields", not thin,
         f"every publish player carries >= 3 transformed bio fields "
         f"(min {min(counts)}, mean {statistics.mean(counts):.2f})"
         if not thin else f"{len(thin)} thin: {thin[:5]}")

    # ---- G7 no stat lines in publish --------------------------------------
    leak = []
    for t in pub["teams"]:
        for p in t["players"]:
            if p["statLines"] is not None:
                leak.append(p["name"])
            for a in p["careerArc"]:
                if a["gp"] is not None or a["gs"] is not None:
                    leak.append(p["name"] + " (arc gp/gs)")
                    break
    gate(res, "publish-ovr-arcs-only", not leak,
         "publish carries OVR arcs only — statLines null and no gp/gs on any arc row"
         if not leak else f"{len(leak)} leaks: {leak[:5]}")

    # ---- G8 calibration ----------------------------------------------------
    all_ovr = [p["ratingTarget"] for t in dev["teams"] for p in t["players"]]
    mean, sd = statistics.mean(all_ovr), statistics.pstdev(all_ovr)
    tmeans = {t["identity"]["key"]: statistics.mean([p["ratingTarget"] for p in t["players"]])
              for t in dev["teams"]}
    spread = max(tmeans.values()) - min(tmeans.values())
    raw_wins = {t["abbr"]: t["record2025"]["wins"] for t in raw["teams"]}
    keys = list(tmeans.keys())
    corr = spearman([tmeans[k] for k in keys], [raw_wins[k] for k in keys])
    ok = (CALIB_MEAN_BAND[0] <= mean <= CALIB_MEAN_BAND[1]
          and CALIB_SD_BAND[0] <= sd <= CALIB_SD_BAND[1]
          and TEAM_SPREAD_BAND[0] <= spread <= TEAM_SPREAD_BAND[1]
          and corr >= TEAM_STRENGTH_CORR_MIN)
    gate(res, "calibration-bands", ok,
         f"league mean {mean:.2f} (band {CALIB_MEAN_BAND}), sd {sd:.2f} "
         f"(band {CALIB_SD_BAND}), team spread {spread:.2f} (band {TEAM_SPREAD_BAND}), "
         f"Spearman(team OVR, 2025 wins) {corr:.2f} (min {TEAM_STRENGTH_CORR_MIN})")

    # ---- G9 tier structure -------------------------------------------------
    # Compared on the generator's own terms: its depth index is the player's
    # rank inside (team, position), capped at 2 — the same bucketing the
    # reference pools were built with.
    ref_tiers = blueprint_tier_means()
    tier = defaultdict(list)
    for t in dev["teams"]:
        for p in t["players"]:
            tier[min(p["depthRank"] - 1, 2)].append(p["ratingTarget"])
    deltas = {d: statistics.mean(tier[d]) - ref_tiers[d] for d in (0, 1, 2)}
    tier_ok = (all(abs(v) <= 2.0 for v in deltas.values())
               and statistics.mean(tier[0]) > statistics.mean(tier[1]) > statistics.mean(tier[2]))
    role_summary = {}
    for t in dev["teams"]:
        for p in t["players"]:
            role_summary.setdefault(p["role"], []).append(p["ratingTarget"])
    gate(res, "tier-structure", tier_ok,
         "depth-index means vs the random generator: " + ", ".join(
             f"idx{d} {statistics.mean(tier[d]):.1f} (ref {ref_tiers[d]:.1f}, "
             f"{deltas[d]:+.2f}, n={len(tier[d])})" for d in (0, 1, 2))
         + "; by role " + ", ".join(f"{k} {statistics.mean(v):.1f} (n={len(v)})"
                                    for k, v in sorted(role_summary.items()))
         + f"; league max {max(all_ovr)}, 90+ count {sum(1 for v in all_ovr if v >= 90)}")

    # ---- G10 depth order re-derivable + hand corrections ------------------
    depth_viol = []
    for t in dev["teams"]:
        by_pos = defaultdict(list)
        for p in t["players"]:
            by_pos[p["pos"]].append(p)
        for pos, g in by_pos.items():
            ranked = sorted(g, key=lambda q: q["depthRank"])
            for a, b in zip(ranked, ranked[1:]):
                if a["ratingTarget"] < b["ratingTarget"]:
                    depth_viol.append(f"{t['identity']['key']} {pos}: rank order != rating order")
    # the two named QB corrections, checked through the stable id
    named = []
    for team_abbr, pos, better, worse, _m, _w in HAND_DEPTH_OVERRIDES:
        bid = stable_id("player", team_abbr, better, pos)
        wid = stable_id("player", team_abbr, worse, pos)
        t = next(x for x in dev["teams"] if x["identity"]["key"] == team_abbr)
        bp = next((p for p in t["players"] if p["id"] == bid), None)
        wp = next((p for p in t["players"] if p["id"] == wid), None)
        if not bp or not wp or bp["depthRank"] >= wp["depthRank"]:
            named.append(f"{team_abbr} {pos}: correction did not take")
        else:
            named.append(f"{team_abbr} {pos}: OK — QB1 {bp['ratingTarget']} OVR "
                         f"vs QB{wp['depthRank']} {wp['ratingTarget']} OVR")
    inversions = 0
    ratings = ctx["ratings"]
    for s in raw["qa"].get("depthOrderSuspects", []):
        kb = (s["team"], s["benched"], s["pos"])
        kw = (s["team"], s["listedStarter"], s["pos"])
        if kb in ratings and kw in ratings and ratings[kb] < ratings[kw]:
            inversions += 1
    ok = not depth_viol and all("OK" in n for n in named) and inversions == 0
    gate(res, "depth-order-from-ratings", ok,
         f"depth rank is the rating order on all 32 rosters; "
         f"{len(raw['qa'].get('depthOrderSuspects', []))} QA depth suspects resolved "
         f"({inversions} inversions left); " + "; ".join(named)
         if ok else f"{len(depth_viol)} order breaks; {named}; {inversions} inversions")

    # ---- G11 jerseys -------------------------------------------------------
    jviol = []
    for label, doc in (("dev", dev), ("publish", pub)):
        for t in doc["teams"]:
            seen_j = defaultdict(list)
            for p in t["players"]:
                seen_j[p["jersey"]].append(p["name"])
            for num, names in seen_j.items():
                if len(names) > 1:
                    jviol.append(f"{label}/{t['identity']['key']} #{num}: {names}")
    gate(res, "jersey-uniqueness", not jviol,
         "no duplicate jersey number on any roster in either profile "
         "(the 2 raw collisions were reassigned)" if not jviol else f"{jviol[:5]}")

    # ---- G12 pick trade notes ---------------------------------------------
    note_hits = []
    for t in pub["teams"]:
        for pk in t["picks2026"]:
            v = pk.get("via")
            if not v:
                continue
            for real in blocklist["full"]:
                if real in v:
                    note_hits.append(v)
                    break
    gate(res, "publish-pick-notes-clean", not note_hits,
         "every 2026 pick trade note is reduced to the ownership chain "
         "('from X via Y'); no player names survive"
         if not note_hits else f"{note_hits[:3]}")

    # ---- G13 draft-pick fuzz ----------------------------------------------
    real_pick = {}
    for t in raw["teams"]:
        for p in t["players"]:
            if p.get("draft") and p["draft"].get("pick") is not None:
                real_pick[stable_id("player", t["abbr"], p["name"], p["pos"])] = p["draft"]["pick"]
    same = 0
    total = 0
    for t in pub["teams"]:
        for p in t["players"]:
            if p["id"] in real_pick:
                total += 1
                if p["fuzzedPick"] == real_pick[p["id"]]:
                    same += 1
    gate(res, "publish-draft-slot-fuzzed", same == 0,
         f"{total} drafted players; 0 keep their real overall pick "
         f"(round preserved, slot moved within round)"
         if same == 0 else f"{same}/{total} kept the real slot")

    # ---- G14 publish jersey reassignment ----------------------------------
    real_jersey = {}
    for t in raw["teams"]:
        for p in t["players"]:
            real_jersey[stable_id("player", t["abbr"], p["name"], p["pos"])] = p["jersey"]
    kept = [p["name"] for t in pub["teams"] for p in t["players"]
            if real_jersey.get(p["id"]) == p["jersey"]]
    gate(res, "publish-jersey-reissued", not kept,
         "no publish player wears his real number (the Keller/Davis "
         "'number + position + bio' combination is broken); numbers stay inside "
         "the position's legal NFL bands and unique per roster"
         if not kept else f"{len(kept)} kept their real number: {kept[:5]}")

    # ---- G15 no free-text notes in publish --------------------------------
    # `notes` is not in the publish payload `ANONYMIZATION_SPEC.md` allows at
    # all, and the one it used to carry — "finished 2025 on injured reserve" —
    # is a real medical fact about a named person (§3: no real injury timeline
    # ships). Combined with the team + position + depth rank the profile keeps
    # BY DESIGN, it identified single players out of the bundle.
    noted = [f"{t['identity']['key']}/{p['name']}: {p['notes']}"
             for t in pub["teams"] for p in t["players"] if p["notes"] is not None]
    dev_noted = sum(1 for t in dev["teams"] for p in t["players"] if p["notes"])
    gate(res, "publish-no-notes-payload", not noted,
         f"no publish player carries a `notes` payload (the dev profile keeps "
         f"{dev_noted} of them, incl. the real injured-reserve flag, and is "
         "DEBUG-only)" if not noted else f"{len(noted)} carry notes: {noted[:5]}")

    # ---- G16 recombination of the shipped name tokens ---------------------
    # The surface the runtime `SupportStaffNamePool` actually harvests.
    pub_first = sorted({p["firstName"] for t in pub["teams"] for p in t["players"]})
    pub_last = sorted({p["lastName"] for t in pub["teams"] for p in t["players"]})
    recomb = sorted(recombination_conflicts(pub_first, pub_last, blocklist["fullNorm"]))
    gate(res, "publish-name-recombination>=3", not recomb,
         f"all {len(pub_first)} x {len(pub_last)} = {len(pub_first) * len(pub_last)} "
         "recombinations of the shipped first/last tokens are Levenshtein >= 3 from "
         "every real name — the importer generates 417 support-staff coaches by "
         "drawing the two halves independently, and those names never reach a "
         "bundle scan" if not recomb
         else f"{len(recomb)} dirty recombinations: {recomb[:5]}")

    # ---- G17 coach tenure jitter -------------------------------------------
    real_since = {}
    for abbr, staff in raw["staffs"]["staffs"].items():
        for slot, key in (("hc", "headCoach"), ("oc", "offensiveCoordinator"),
                          ("dc", "defensiveCoordinator")):
            s = staff.get(key)
            if s and s.get("sinceYear"):
                real_since[(abbr, slot)] = s["sinceYear"]
    tenure_kept = []
    checked = 0
    for t in pub["teams"]:
        for slot in ("hc", "oc", "dc"):
            s = t["staff"].get(slot)
            k = (t["identity"]["key"], slot)
            if not s or k not in real_since:
                continue
            checked += 1
            if s["sinceYear"] == real_since[k]:
                tenure_kept.append(f"{k[0]}/{slot} {s['sinceYear']}")
    gate(res, "publish-coach-tenure-moved", not tenure_kept,
         f"all {checked} publish coaches with a real `sinceYear` moved by exactly "
         "±1 (spec §4); the direction is picked among the moves that survive the "
         "[1990, leagueYear] clamp, so a 2026 hire cannot be clamped back onto his "
         "real tenure" if not tenure_kept
         else f"{len(tenure_kept)}/{checked} kept the real year: {tenure_kept[:6]}")

    # ---- G18 age profile (accepted difference, guarded against drift) ------
    # DIAGNOSTIC + drift guard, deliberately NOT a match against the random
    # generator: `ANONYMIZATION_SPEC.md` §2 requires the real age pyramid to be
    # PRESERVED (age jitter is exactly balanced), so the template sits older than
    # `LeagueGenerator.randomAge` by construction — see TRANSFORM_QA §7.
    ages = [p["age"] for t in pub["teams"] for p in t["players"]]
    age_mean = statistics.mean(ages)
    share33 = 100.0 * sum(1 for a in ages if a >= 33) / len(ages)
    roster_sizes = sorted({len(t["players"]) for t in pub["teams"]})
    age_ok = 25.0 <= age_mean <= 28.0 and share33 <= 8.0
    gate(res, "age-profile-in-drift-band", age_ok,
         f"mean age {age_mean:.1f} (band 25.0-28.0), 33+ share {share33:.1f}% "
         f"(ceiling 8.0%), roster sizes {roster_sizes}. Reference random league: "
         "mean 25.8 / 3.2% at 33+ over exactly 53 men. The template is OLDER on "
         "purpose (real pyramid, real 53+IR rosters) and its first offseason "
         "retires ~86 players against the random league's ~46 — an ACCEPTED, "
         "recorded difference, not a calibration target; see TRANSFORM_QA §7")

    # ---- G19 face pre-assignment -------------------------------------------
    face_err = []
    face_lines = []
    face_baked = []
    for label, doc in (("dev", dev), ("publish", pub)):
        rep = ctx["faces"][label]
        ids, missing, out_of_range = [], [], []
        for t in doc["teams"]:
            for p in t["players"]:
                (ids.append(p["faceID"]) if p.get("faceID") else
                 missing.append(f"{t['identity']['key']}/{p['name']}"))
            for slot in ("hc", "oc", "dc"):
                s = t["staff"].get(slot)
                if s is None:
                    continue
                (ids.append(s["faceID"]) if s.get("faceID") else
                 missing.append(f"{t['identity']['key']}/{slot}"))
        face_baked.extend(ids)
        for fid in ids:
            if not re.fullmatch(r"face_\d{5}", fid) or not (0 <= int(fid[5:]) < FACE_POOL):
                out_of_range.append(fid)
        seen_face = defaultdict(int)
        for fid in ids:
            seen_face[fid] += 1
        dupes = sorted(fid for fid, n in seen_face.items() if n > 1)
        if missing:
            face_err.append(f"{label}: {len(missing)} people without a face ({missing[:3]})")
        if out_of_range:
            face_err.append(f"{label}: {len(out_of_range)} malformed ids ({out_of_range[:3]})")
        if dupes:
            face_err.append(f"{label}: {len(dupes)} faces used twice ({dupes[:5]})")
        if rep["roleMismatch"]:
            face_err.append(f"{label}: {rep['roleMismatch']} people wear the other role's face")
        # The reserve range (ids the default `--count 2048` run does NOT
        # produce) must be a strict SUFFIX of the visibility order: nobody more
        # visible than a reserve holder may sit on a generated-range face.
        reserve_ranks = [rank for rank, _, _, _ in rep["reserve"]]
        if reserve_ranks:
            first_reserve = min(reserve_ranks)
            leaked = [fid for fid, rank in rep["order"].items()
                      if rank > first_reserve and int(fid[5:]) < FACE_GENERATED_POOL]
            if leaked:
                face_err.append(f"{label}: {len(leaked)} generated-range faces went to "
                                f"people below the first reserve holder")
            bad_role = sorted({role for _, kind, role, _ in rep["reserve"]
                               if kind != "player" or role not in ("backup", "depth")})
            if bad_role:
                face_err.append(f"{label}: reserve faces reached {bad_role}")
        band = 100.0 * rep["bandMatch"] / max(1, rep["assigned"])
        build = 100.0 * rep["buildMatch"] / max(1, rep["assigned"])
        if band < FACE_BAND_MATCH_MIN:
            face_err.append(f"{label}: age-band match {band:.1f}% < {FACE_BAND_MATCH_MIN}%")
        if build < FACE_BUILD_MATCH_MIN:
            face_err.append(f"{label}: build match {build:.1f}% < {FACE_BUILD_MATCH_MIN}%")
        face_lines.append(
            f"{label} {rep['assigned']} unique faces ({rep['players']}p + {rep['coaches']}c), "
            f"band {band:.1f}%, build {build:.1f}%, exact bucket "
            f"{100.0 * rep['exactBucket'] / max(1, rep['assigned']):.1f}%, "
            f"{len(rep['reserve'])} reserve"
        )

    # Female coach faces live only in the extended range, and the template's 96
    # named coaches are all male (they anonymize real male head coaches, so a
    # woman there would be a gate-16 surface nobody has checked). `_face_take`
    # hands out the lowest free id first and the template never reaches
    # face_02560+, so the baked count below is expected to stay 0 — record both
    # numbers so the day it stops being 0 is visible in the gate line.
    _pool = face_pool()
    female_supply = sum(1 for b in _pool if b.get("gender") == "female")
    female_baked = sum(1 for fid in face_baked
                       if re.fullmatch(r"face_\d{5}", fid)
                       and 0 <= int(fid[5:]) < FACE_POOL
                       and _pool[int(fid[5:])].get("gender") == "female")
    face_lines.append(f"{female_supply} female coach faces in the pool "
                      f"(ids {FACE_FEMALE_RANGE_START}+), {female_baked} baked")

    # Cross-check the bucket maths against the real generator output whenever
    # the (dev-only, unbundled) raw manifest is around. It is the one place the
    # transcription of `generate_faces.py::build_spec` can actually be falsified.
    live = os.path.join(os.path.dirname(HERE), "faces", "manifest.json")
    checked = 0
    if os.path.exists(live):
        try:
            gen = json.load(open(live, encoding="utf-8"))
            for f in gen.get("faces", []):
                index = int(f["id"][5:])
                checked += 1
                if face_bucket(index) != f["bucket"]:
                    face_err.append(f"bucket mismatch vs generator on {f['id']}")
                    break
        except (OSError, ValueError, KeyError) as exc:
            face_err.append(f"could not read {live}: {exc}")

    gate(res, "face-preassignment", not face_err,
         "; ".join(face_lines)
         + f"; buckets cross-checked against {checked} generated faces"
         + f"; pool {FACE_GENERATED_POOL} generated + {FACE_RESERVE_POOL} reserve"
         + f" + {FACE_FEMALE_POOL} extended"
         if not face_err else "; ".join(face_err[:5]))

    return res


# ---------------------------------------------------------------------------
# 15. TRANSFORM_QA.md
# ---------------------------------------------------------------------------


def write_qa_report(path, dev, pub, ctx, gates, log):
    raw = ctx["raw"]
    all_ovr = [p["ratingTarget"] for t in dev["teams"] for p in t["players"]]
    tmeans = sorted(((statistics.mean([p["ratingTarget"] for p in t["players"]]),
                      t["identity"]["key"]) for t in dev["teams"]), reverse=True)
    wins = {t["abbr"]: t["record2025"] for t in raw["teams"]}

    # 20-player blind recognizability sample
    rng = seeded("qasample")
    flat = [(t["identity"]["key"], p) for t in pub["teams"] for p in t["players"]]
    flat.sort(key=lambda x: x[1]["id"])
    sample = rng.sample(flat, 20)
    real_lookup = {}
    for t in raw["teams"]:
        for p in t["players"]:
            real_lookup[stable_id("player", t["abbr"], p["name"], p["pos"])] = (t["abbr"], p)

    lines = []
    A = lines.append
    A("# TRANSFORM_QA — league template build")
    A("")
    A("> **DO NOT BUNDLE.** This report is a tool artifact. It contains the answer key")
    A("> for the recognizability spot-check (real names) in the final section and must")
    A("> never enter an app target's resources. `league_2026_dev.json` is DEBUG-only;")
    A("> only `league_2026_publish.json` ships in a Release build.")
    A("")
    A(f"- built: `{_dt.datetime.now(_dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}` "
      f"(the templates themselves are byte-identical on every rebuild — their "
      f"`generated` stamp is the source snapshot's, `{dev['generated']}`)")
    A(f"- globalSeed: `{GLOBAL_SEED}` (deterministic — re-running reproduces both files)")
    A(f"- source: `{dev['source']['raw']}` (schemaVersion {dev['source']['rawSchemaVersion']}, "
      f"snapshot {dev['source']['snapshotDate']})")
    A(f"- outputs: `out/league_2026_dev.json` (devProfile), "
      f"`out/league_2026_publish.json` (publishProfile)")
    A(f"- teams 32 / players {len(all_ovr)} / coaches "
      f"{sum(1 for t in pub['teams'] for s in ('hc', 'oc', 'dc') if t['staff'][s])}")
    A("")

    A("## 1. Gate results")
    A("")
    A("| # | Gate | Result | Detail |")
    A("|---:|---|:-:|---|")
    for i, g in enumerate(gates, 1):
        A(f"| {i} | `{g['gate']}` | {'PASS' if g['pass'] else '**FAIL**'} | {g['detail']} |")
    A("")
    verdict = "ALL GATES PASS" if all(g["pass"] for g in gates) else "FAILED"
    A(f"**Verdict: {verdict}.**")
    A("")

    A("## 2. Calibration")
    A("")
    A("Binding decision: the template league must sit where the *random* "
      "`LeagueGenerator` league sits, so every balance threshold in the engine "
      "behaves identically across all three league sources. It is **not** "
      "recalibrated to `DEVELOPMENT_NFL_REFERENCE.md` section-8 absolute bands.")
    A("")
    A("Method: the tool Monte-Carlos the Swift generator "
      f"({REF_SIM_REPS} reps) over *this* league's actual composition — same "
      "positions, same per-team depth counts, same real ages — and then rank-maps "
      "each position's players onto that position's reference quantile curve. The "
      "level and shape therefore match by construction; only the ORDERING inside a "
      "position comes from the production model.")
    A("")
    A(f"- league mean OVR **{statistics.mean(all_ovr):.2f}** "
      f"(reference generator 76.46, band {CALIB_MEAN_BAND})")
    A(f"- league sd **{statistics.pstdev(all_ovr):.2f}** (reference 8.23, band {CALIB_SD_BAND})")
    A(f"- team mean spread **{tmeans[0][0] - tmeans[-1][0]:.2f}** OVR "
      f"(target {TEAM_SPREAD_TARGET}, band {TEAM_SPREAD_BAND})")
    A(f"- OVR 90+: {sum(1 for v in all_ovr if v >= 90)} players; max {max(all_ovr)}; "
      f"min {min(all_ovr)}")
    A("")
    A("### Team strength vs real 2025")
    A("")
    A("| Team | mean OVR | 2025 record | playoff finish |")
    A("|---|---:|---|---|")
    for m, abbr in tmeans:
        r = wins[abbr]
        A(f"| {abbr} | {m:.1f} | {r['wins']}-{r['losses']}"
          f"{'-' + str(r['ties']) if r['ties'] else ''} | {r.get('playoffResult') or '—'} |")
    A("")

    A("## 3. Ratings derivation (position heuristics)")
    A("")
    A("Per player: `quality = (1 - w_ped) * (0.60 * production + 0.40 * role) "
      "+ w_ped * draftPedigree`, with `w_ped = 0.32 * exp(-yearsPro / 2.2)` so "
      "draft capital carries a rookie and is irrelevant to a nine-year veteran. "
      "A small age term (half of the generator's own `ageLevelShift`) keeps the "
      "age/rating relationship the engine sustains.")
    A("")
    A("`production` is never an absolute number: every metric below is converted "
      "to a percentile inside `(position family, season)`, weighted, then shrunk "
      "toward the median by a confidence factor built from games played and snap "
      "share — a four-game cameo cannot make or break a rating. Seasons are "
      "recency-weighted `0.62^(2025 - year)`.")
    A("")
    A("| Family | Metrics (weight) |")
    A("|---|---|")
    for fam, w in METRIC_WEIGHTS.items():
        A(f"| {fam} | " + ", ".join(f"`{k}` {v:.2f}" for k, v in w.items()) + " |")
    A("")
    A("`areaHints` are mean-zero integer deltas (±8 max) on the game's own "
      "position-attribute names, so they tilt the shape without moving the solved "
      "overall: QB accuracy vs arm vs scrambling from comp% / yds-per-attempt / "
      "rush profile and sack rate; RB elusiveness vs power from yards-per-carry, "
      "weight and receiving share; WR hands vs deep from catch rate and "
      "yards-per-reception; TE blocking vs receiving from target rate; OL "
      "pass-set vs pull from the exact position, weight and penalty rate; DL "
      "power vs finesse from weight against sack rate; LB coverage vs blitz from "
      "passes-defensed against sacks; DB coverage vs run-support from "
      "(PD + 2.5·INT)/g against tackles/g, plus height for press.")
    A("")
    A("`potential` is the phase-2 veteran rule ported verbatim "
      "(`LeagueGenerator.veteranPotential`): past the position's peak window the "
      "ceiling is `overall + U(0,3)`; inside it, `overall + max(0, N(mu, 4))` with "
      "`mu = max(2, 14 - 2.5·(age - 22))`.")
    A("")
    A("`careerArc` = per-season production percentile → OVR band → ±2 seeded "
      "jitter, anchored so the 2025 row lands within ±3 of `ratingTarget`. "
      "In the publish file this is the ONLY career record that ships.")
    A("")

    A("## 4. QA_REPORT carry-in conditions")
    A("")
    A("| # | Carry-in | Handling |")
    A("|---:|---|---|")
    A("| 1 | `role` is a one-season volume ranking, 27/768 starter slots suspect | "
      "Production model is rate-based, and depth order is **re-derived from the "
      "ratings** in both profiles (`depthRank` / `role`); the raw values survive "
      "only as `roleHint` / `depthRankHint`. All 27 machine-listed suspects are "
      "lifted above their listed starter in score space; CIN QB and WAS QB are "
      "additionally forced by an explicit hand override. |")
    A("| 2 | 2 jersey collisions (BUF #23, IND #17) | Higher-rated player keeps the "
      "number, the other is reassigned to the lowest free number on that roster. |")
    A("| 3 | 5 null colleges | Replaced by the `\"No College\"` sentinel; in "
      "publish they go through the same same-tier swap as everyone else, because a "
      "\"No College\" flag on 5 players is itself an identifier. Transfer chains "
      "(`\"LSU; Ohio State\"`) are reduced to the school of record, which nflverse "
      "lists FIRST. |")
    A("| 4 | OL `gs` is a `snapStart50` proxy | OL production is scored on snap "
      "share / snaps-per-game / penalty rate — never on `gs`. |")
    A("| 5 | Anonymization is mandatory | Both profiles are anonymized; the publish "
      "profile additionally passes gates 2-7 and 12-13 above. |")
    A("")
    for line in ctx["depth_fixes"][:6]:
        A(f"- {line}")
    if len(ctx["depth_fixes"]) > 6:
        A(f"- … {len(ctx['depth_fixes']) - 6} further depth corrections")
    A("")

    A("## 5. Anonymization")
    A("")
    A("**devProfile** (`league_2026_dev.json`, DEBUG builds only): sound-alike "
      "names produced by swapping the onset consonant clusters between first and "
      "last name and applying one seeded phonetic texture tweak to each half — "
      "`Jared Goff` → `Gared Joff` → `Garret Joff`. Team identities are real city "
      "+ real-adjacent nickname. Exact stat lines are carried in `statLines`.")
    A("")
    A("**publishProfile** (`league_2026_publish.json`, bundled always), per "
      "`docs/ANONYMIZATION_SPEC.md`:")
    A("")
    A(f"- Names drawn independently from a {len(ctx['factory'].first_pool)} × "
      f"{len(ctx['factory'].last_pool)} pool, culturally mixed and blocklist-filtered "
      "and far larger than the game's own `RandomNameGenerator` pool. "
      "Seed = SHA-256(globalSeed | real name | team | pos).")
    A(f"- Blocklist: {len(ctx['blocklist']['full'])} real names — every player and "
      "coach in the raw snapshot plus a curated list of notable NFL figures of the "
      "last ~15 years.")
    A("- Guards: full-name Levenshtein ≥ 3 to every blocklisted name; generated "
      "surname not equal to and not a 1-edit variant of any real surname; no "
      "duplicate generated names; no same-initials + same-team + same-position hit.")
    A("- Guard 1c — **recombination**: the emitted first / last tokens become a "
      "POOL. `LeagueTemplateImporter.SupportStaffNamePool` harvests them and draws "
      "the halves independently for 417 runtime support-staff coaches, so the "
      "constraint is not \"the pairs I emit are clean\" but \"every pair the emitted "
      "tokens can form is clean\". The factory refuses any token that would break "
      f"that ({ctx['factory'].stats['recombinationRejected']} rejections this "
      "build), and gate 16 re-derives the whole cross product. Without it "
      "`Cedric`+`Skillman`, `Zaire`+`Frankland` and `Broderick`+`Warrington` were "
      "all reachable at 2 edits from a real player — at run time, where no bundle "
      "scan can see them.")
    A("- Bio jitter: age ±1 (exactly balanced league-wide, so the age pyramid is "
      "preserved), `yearsPro` re-clamped to `[0, age-20]`, college swapped for a "
      "different school of the same tier (P5/G5/FCS; two players who really shared "
      "a school and a draft class never share the replacement), draft year and "
      "round kept with the pick fuzzed ±8 inside the round, height ±1 in, weight "
      "±2-4 %.")
    A("- Jersey numbers reissued from the position's legal NFL bands, unique per "
      "roster, never the real number. `ANONYMIZATION_SPEC.md` section 0 does not "
      "list the number, but the precedent it cites (Keller / Davis v. EA) turns "
      "on exactly \"number + position + bio + stats\" — a #9 quarterback in "
      "Cincinnati is identifiable to any fan — so this tool transforms it.")
    A("- Careers: OVR arcs only. `statLines` is `null` and no arc row carries "
      "games played / started.")
    A("- `notes` is `null` for every publish player (gate 15). The dev profile "
      "keeps `undrafted` / `finished 2025 on injured reserve`; the IR flag is a "
      "real medical event for a named person, which section 3 does not ship, and "
      "against the team + position + depth rank the profile keeps by design it "
      "identified single players straight out of the bundle.")
    A("- Coaches: fictional names, `sinceYear` ±1 with the DIRECTION chosen among "
      "the moves that survive the [1990, leagueYear] clamp (drawing first and "
      "clamping second returned the real year for every 2026 hire), offense/defense "
      "background and scheme identity kept, lineage notes dropped.")
    A("- Team identities: real cities kept (facts / the game's own setup), "
      "nicknames fully fictional.")
    A("- Pick trade notes reduced to the ownership chain (`from SEA via JAX`); the "
      "prose that names players is dropped.")
    A("")

    A("## 6. Recognizability spot-check — 20-player blind sample")
    A("")
    A("Read this table without scrolling to the answer key. Per "
      "`ANONYMIZATION_SPEC.md` section 6.4, a reviewer who knows the NFL must not be "
      "able to name the real counterpart from the in-app profile alone. Any "
      "confident hit means the offending field's jitter needs tightening and a "
      "regeneration.")
    A("")
    A("| # | Name | Team | Pos | # | Age | Exp | College | Ht/Wt | Draft | OVR | Pot |")
    A("|---:|---|---|---|---:|---:|---:|---|---|---|---:|---:|")
    for i, (abbr, p) in enumerate(sample, 1):
        ht = f"{p['heightIn'] // 12}-{p['heightIn'] % 12}"
        draft = (f"{p['draftYear']} R{p['draftRound']} #{p['fuzzedPick']}"
                 if p["draftYear"] else "UDFA")
        A(f"| {i} | {p['name']} | {abbr} | {p['pos']} | {p['jersey']} | {p['age']} | "
          f"{p['yearsPro']} | {p['college']} | {ht} / {p['weightLb']} | {draft} | "
          f"{p['ratingTarget']} | {p['potential']} |")
    A("")
    A("### Answer key — real counterparts (DO NOT BUNDLE)")
    A("")
    A("| # | Publish name | Real name | Real college | Real ht/wt | Real draft |")
    A("|---:|---|---|---|---|---|")
    for i, (abbr, p) in enumerate(sample, 1):
        r_abbr, r = real_lookup[p["id"]]
        rd = r.get("draft")
        rds = f"{rd['year']} R{rd['round']} #{rd['pick']}" if rd else "UDFA"
        rht = f"{r['heightIn'] // 12}-{r['heightIn'] % 12}"
        A(f"| {i} | {p['name']} | {r['name']} | {r.get('college') or NO_COLLEGE} | "
          f"{rht} / {r['weightLb']} | {rds} |")
    A("")

    A("## 7. Age profile — a KNOWN, ACCEPTED difference from the random league")
    A("")
    ages = [p["age"] for t in pub["teams"] for p in t["players"]]
    hist = defaultdict(int)
    for a in ages:
        hist[a] += 1
    A("The calibration decision binds OVR **level and spread**. It does not bind "
      "the age pyramid, and the two league sources deliberately disagree there:")
    A("")
    A("| | Fixed 2026 template | Random `LeagueGenerator` |")
    A("|---|---:|---:|")
    A(f"| mean age | **{statistics.mean(ages):.1f}** | 25.8 |")
    A(f"| median age | **{statistics.median(ages):.0f}** | 25 |")
    A(f"| share 33+ | **{100.0 * sum(1 for a in ages if a >= 33) / len(ages):.1f}%** | 3.2% |")
    A(f"| roster size | **{min(len(t['players']) for t in pub['teams'])}-"
      f"{max(len(t['players']) for t in pub['teams'])}** (real 53-man + IR) | exactly 53 |")
    A("| measured season-1 retirements | **~86** | ~46 |")
    A("| measured season-1 draft intake | **288** | 250 |")
    A("")
    A("Age histogram: " + ", ".join(f"{a}:{hist[a]}" for a in sorted(hist)))
    A("")
    A("Why it is not \"fixed\": `ANONYMIZATION_SPEC.md` section 2 requires the age "
      "pyramid to be PRESERVED (that is why the ±1 jitter is exactly balanced), and "
      "the pyramid is the realism the template exists to deliver. Reshaping it onto "
      "`LeagueGenerator.randomAge` — which is `min(U, U)`, deliberately young — "
      "would replace real 2026 rosters with a synthetic age curve.")
    A("")
    A("What it costs: `PlayerRetirementEngine.retirementProbability` is "
      "`0.04 + yearsPastPeak * 0.19`, so a Fixed 2026 career's FIRST offseason "
      "cycles about 4.8 % of the league out against the random league's 2.7 %, and "
      "backfills from a draft pipeline calibrated for 250. It is a season-1 churn "
      "spike, not a permanent divergence: by the end of season 1 the 33+ share is "
      "0.8 %, rosters are 53/53, and league mean OVR lands 75.68 (template) vs "
      "75.97 (random). Both leagues also sit above `DEVELOPMENT_NFL_REFERENCE.md` "
      "section 8's <=2 % band for 33+, which the deferred P1 recalibration wave owns "
      "— fixing the template alone would just move it away from the random league it "
      "is required to match.")
    A("")
    A("Gate 18 (`age-profile-in-drift-band`) therefore records the numbers and only "
      "fails on DRIFT (mean outside 25.0-28.0, or 33+ above 8 %), so a future raw "
      "snapshot cannot quietly make this worse.")
    A("")

    A("## 8. Face pre-assignment (phase 4)")
    A("")
    faces = ctx["faces"]["publish"]
    pool = face_pool()
    supply = defaultdict(int)
    for i, b in enumerate(pool):
        supply[(b["role"], b["ageBand"], "gen" if i < FACE_GENERATED_POOL else "res")] += 1
    demand = defaultdict(int)
    for t in pub["teams"]:
        for p in t["players"]:
            demand[("player", face_player_band(p["age"]))] += 1
        for slot in ("hc", "oc", "dc"):
            if t["staff"].get(slot):
                demand[("coach", face_coach_band(template_coach_age(t["identity"]["key"], slot)))] += 1
    A("Every template person carries the face id he will wear. This is not a "
      "convenience: `LeagueTemplateImporter` gives each imported `Player` / "
      "`Coach` a FRESH `UUID()`, and the runtime picker hashes exactly that "
      "UUID — so a fixed league that assigned faces at runtime would show "
      "different portraits every time it was created. Baking the ids is what "
      "makes the fixed league fixed all the way down to the faces.")
    A("")
    A("**Pool decision: the library is extended to 3 584 ids** "
      f"(`face_00000`-`face_{FACE_POOL - 1:05d}`). The seed yields "
      f"{sum(v for (r, _b, s), v in supply.items() if r == 'player' and s == 'gen')} "
      "player-age faces in the default `--count 2048` range against "
      f"{sum(v for (r, _b), v in demand.items() if r == 'player')} template "
      "players, so per-person uniqueness is arithmetically impossible there. "
      "Sharing was rejected (a duplicated portrait inside ONE league reads as a "
      "bug), so the transform draws the overflow from a reserved range, "
      f"`face_{FACE_GENERATED_POOL:05d}`-`face_{FACE_POOL - 1:05d}`, which "
      "`python3 tools/faces/generate_faces.py --count 3584` produces later. Ids "
      "are stable and the manifest is append-only, so extending costs nothing "
      "already generated.")
    A("")
    A(f"The last {FACE_FEMALE_POOL} ids "
      f"(`face_{FACE_FEMALE_RANGE_START:05d}`-`face_{FACE_POOL - 1:05d}`) are the "
      "**female extension range**: a coach face there spends one extra draw on "
      f"gender at {FACE_FEMALE_COACH_SHARE:.0%}, and it is the library's only "
      "source of female portraits. The template never reaches it — its coaches "
      "anonymize real male head coaches and allocation is lowest-id-first — so "
      "the range exists purely for the women a career hires at run time.")
    A("")
    A("| pool half | age band | faces `--count 2048` | + ids 2048+ | template demand |")
    A("|---|---|---:|---:|---:|")
    for role in ("player", "coach"):
        for band in FACE_AGE_ORDER[role]:
            A(f"| {role} | {band} | {supply[(role, band, 'gen')]} | "
              f"+{supply[(role, band, 'res')]} | {demand[(role, band)]} |")
    A("")
    A(f"- assigned: **{faces['assigned']} unique faces** "
      f"({faces['players']} players + {faces['coaches']} coaches), zero shared, "
      f"zero role mismatches (no player wears a coach-age face)")
    A(f"- bucket quality: age band exact on **{100.0 * faces['bandMatch'] / faces['assigned']:.1f} %**, "
      f"build exact on **{100.0 * faces['buildMatch'] / faces['assigned']:.1f} %**, both "
      f"on {100.0 * faces['exactBucket'] / faces['assigned']:.1f} %. The rest take the "
      "nearest neighbouring bucket — build is relaxed BEFORE age, exactly as "
      "`FaceLibrary.pickLocked` does at runtime.")
    A(f"- reserve range: **{len(faces['reserve'])} people** — the whole "
      f"{sum(1 for _r, _k, role, _f in faces['reserve'] if role == 'depth')}-man "
      "`depth` tier plus the "
      f"{sum(1 for _r, _k, role, _f in faces['reserve'] if role == 'backup')} "
      "lowest-rated backups. Allocation runs starters → rotation → backups → "
      "depth and takes the lowest free id first, so the ids whose pictures may "
      "not exist yet land on the least visible people, and the ids generated "
      "first land on the most visible ones.")
    A(f"- left for the career: **{faces['freeGenerated']}** generated-range and "
      f"{faces['freeReserve']} faces at `face_{FACE_GENERATED_POOL:05d}`+ "
      "(reserve plus the female extension range) for draft classes, UDFAs, "
      "hired coordinators and the 417 support-staff coaches the importer "
      "creates.")
    A("")
    A("Nothing here needs an image. A face's bucket is a pure function of "
      "`(face seed, id)`, so this runs while the library is still generating, "
      "and `PersonFaceView` draws a silhouette for any id whose HEIC has not "
      "landed. Gate 19 cross-checks the bucket maths against every face the "
      "generator has actually produced.")
    A("")
    A("One coupling to know about: a template coach has no age in the file — "
      "`LeagueGenerator.generateCoach` draws it. The tool replays that single "
      "draw (SplitMix64 + Swift's 64-bit `Int.random`) to pick an age-correct "
      "face. It is the FIRST draw of the coach's stream only because "
      "`nameOverride` short-circuits the name pools for hc/oc/dc; a new draw "
      "inserted ahead of it would push template coach faces onto the wrong age "
      "band (gate 19's band share would drop to ~50 %).")
    A("")

    A("## 9. Build log")
    A("")
    for line in log:
        A(f"- {line}")
    A("")

    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


# ---------------------------------------------------------------------------
# 16. main
# ---------------------------------------------------------------------------


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)

    log = []
    raw = load_raw(RAW_PATH)
    log.append(f"raw: {len(raw['teams'])} teams / "
               f"{sum(len(t['players']) for t in raw['teams'])} players / "
               f"{sum(len(p['seasons']) for t in raw['teams'] for p in t['players'])} season rows")

    dev, pub, ctx = build_templates(raw, log)
    gates = run_gates(dev, pub, ctx, log)

    os.makedirs(args.out, exist_ok=True)
    dev_path = os.path.join(args.out, "league_2026_dev.json")
    pub_path = os.path.join(args.out, "league_2026_publish.json")
    with open(dev_path, "w", encoding="utf-8") as fh:
        json.dump(dev, fh, ensure_ascii=False, separators=(",", ":"))
    with open(pub_path, "w", encoding="utf-8") as fh:
        json.dump(pub, fh, ensure_ascii=False, separators=(",", ":"))
    qa_path = os.path.join(args.out, "TRANSFORM_QA.md")
    write_qa_report(qa_path, dev, pub, ctx, gates, log)

    if not args.quiet:
        for g in gates:
            print(f"[{'PASS' if g['pass'] else 'FAIL'}] {g['gate']}: {g['detail']}")
        print(f"\nwrote {dev_path} ({os.path.getsize(dev_path) / 1e6:.2f} MB)")
        print(f"wrote {pub_path} ({os.path.getsize(pub_path) / 1e6:.2f} MB)")
        print(f"wrote {qa_path}")

    failed = [g["gate"] for g in gates if not g["pass"]]
    if failed:
        print("\nQA GATES FAILED: " + ", ".join(failed), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
