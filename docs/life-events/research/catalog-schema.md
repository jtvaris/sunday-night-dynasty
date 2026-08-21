# Life Events Catalog — shared schema (all catalog writers MUST follow this exactly)

Output: one JSON file per writer. Top level:

```json
{
  "catalogSection": "k1_legal_discipline",
  "version": "draft-1",
  "targetLeagueYearVolume": { "expectedEventsPerLeagueYear": 41.0, "notes": "sum of all event expectedPerLeagueYear in this file; must match research base rates" },
  "events": [ ... ]
}
```

Each event object:

```json
{
  "id": "k1_dui_offseason_backup",            // stable snake_case, section-prefixed
  "category": "legal",                         // legal | discipline | substance | gambling | personalLife | tragedy | nonFootballInjury | mentalHealth | drama | media | contract | positive | milestone
  "subcategory": "dui",
  "title": "Offseason DUI Arrest",             // short EN label (internal)
  "severityTier": "moderate",                  // minor | moderate | major | career
  "valence": "negative",                       // negative | neutral | positive | contextual (contextual = computed from team record/expectation at fire time)
  "surface": "news",                           // news (feed item) | popup (blocking sheet; majors and everything requiring a user DECISION)
  "headline": "{PLAYER} arrested on DUI charge in {CITY}",   // EN template; placeholders: {PLAYER} {POS} {TEAM} {CITY} {COACH} {AGE} {SPOUSE} — NO real names, NO league trademarks ("the league", "the Championship", never NFL/Super Bowl/Canton/team names)
  "body": "2-4 sentence EN news body template, same placeholder rules. Tone: beat-reporter neutral.",
  "probability": {
    "expectedPerLeagueYear": 6.0,              // league = 32 teams, ~69 players/team (53+16). THE SUM ACROSS YOUR FILE MUST MATCH RESEARCH BASE RATES — cite the research line in "calibration"
    "calendar": [                               // when it can fire; weights sum to 1.0
      { "node": "offseasonMarch", "w": 0.15 }, { "node": "offseasonMay", "w": 0.25 },
      { "node": "trainingCamp", "w": 0.1 }, { "node": "inSeasonWeekly", "w": 0.3 }, { "node": "byeWeek", "w": 0.2 }
      // allowed nodes: offseasonJanuary..offseasonJuly (per month), trainingCamp, preseason, cutdownWeek, inSeasonWeekly, byeWeek, playoffWeek, draftEve, campReportDay, awayGameDay, postSeasonAward
    ],
    "calibration": "r1-legal.md: DUI = 28.3% of 38.6 arrests/yr ≈ 10.9/yr; this template covers the backup/depth slice ≈ 55% of them"
  },
  "eligibility": {
    "positions": ["ANY"],                      // or explicit list
    "ageBand": [21, 34],                       // inclusive
    "starTier": ["depth", "starter"],          // depth | starter | star | superstar (any subset)
    "personalityGates": [                       // ONLY existing fields (see c1-integration-map.md §1) — PlayerPersonality/MentalAttributes are FROZEN; express gates as comparisons on existing fields
      { "field": "PlayerPersonality.discipline", "op": "<=", "value": 40, "effect": "weightMultiplier", "multiplier": 3.0 },
      { "field": "MentalAttributes.composure", "op": "<=", "value": 45, "multiplier": 1.5 }
    ],
    "repeatEscalation": { "sameCategoryPriorCount": 1, "multiplier": 2.5 },   // recidivism from research (23% after one, 32% after two)
    "notes": "who this hits and why, one line"
  },
  "effects": {
    "availability": { "type": "suspension", "games": [1, 3], "list": "reserveSuspended" },  // type: none | suspension | nfi | ir | bereavementDays | personalLeave; games as [min,max] roll; list: reserveSuspended | nfi | none (reserveSuspended does NOT count vs roster, salary forfeits 1/18 per game)
    "performance": { "focusDebuff": -6, "durationWeeks": [2, 6], "note": "temporary, fog-safe (applies to effective ratings, never shown as trueOverall)" },
    "morale": { "player": -10, "lockerRoom": -5, "owner": -8, "fans": -6 },   // the 4-meter vector (EventOption precedent)
    "motivation": { "set": "distracted", "durationWeeks": [4, 8] },           // MotivationState transition or null
    "contract": { "willingnessDelta": -15, "guaranteesVoidRisk": 0.0, "fineAmount": null, "salaryForfeitPerGame": true },
    "development": null                                                        // or { "xpMultiplier": 0.85, "durationWeeks": 8 } for season-long distractions
  },
  "resolution": {                                // OPTIONAL — only for events with a user decision or a multi-stage arc
    "decision": {
      "prompt": "EN template for the coach decision",
      "options": [
        { "label": "Stand by him publicly", "effects": { "morale": { "player": 8, "lockerRoom": 3, "owner": -5, "fans": -4 } }, "followupRisk": "if a second incident fires within 26 weeks, owner -15 extra" },
        { "label": "Suspend him one game (team discipline)", "effects": { "availability": { "type": "suspension", "games": [1,1] }, "morale": { "player": -8, "owner": 6, "fans": 3 } } },
        { "label": "Release him", "effects": { "roster": "release", "morale": { "lockerRoom": -6 } }, "gate": "starTier in [depth]: lockerRoom hit halves" }
      ]
    },
    "arc": [ { "afterWeeks": [6, 20], "fork": [ { "p": 0.31, "outcome": "charges dropped", "headline": "...", "effects": {} }, { "p": 0.5, "outcome": "conviction/plea", "effects": { "availability": { "type": "suspension", "games": [3,3] } } }, { "p": 0.19, "outcome": "diversion", "effects": {} } ] } ]
  },
  "mediaArcDays": [2, 10],
  "playerCard": {                                // REQUIRED whenever the event has availability != none OR any effect with duration >= 1 week
    "badge": "SUSPENDED",                        // short ALL-CAPS chip shown on the player card while the effect is active; null only for pure one-shot news
    "badgeCountdown": "games",                   // games | weeks | none — the chip shows remaining duration ("SUSPENDED · 2 GM", "DISTRACTED · 4 WK")
    "detailLine": "Serving a {N}-game suspension under the league conduct policy",  // EN template for the card's status section
    "historyEntry": true                          // after resolution the event is recorded on the card's career timeline (fogged wording, no hidden values)
  },
  "designNotes": "1-2 lines: research grounding, balance concerns, interactions"
}
```

## HARD RULES
1. English only. NO real people, teams, or league trademarks anywhere (incl. "Super Bowl", "NFL", "Canton", real sponsor names). Fictional analogs only ("the Championship", "the league office", "a national talk show").
2. personalityGates may ONLY reference fields that exist per c1-integration-map.md §1 — read that section first and list the fields you used at the top of your file in a `"personalityFieldsUsed"` array.
3. Calibration discipline: every event carries a `calibration` line tracing its expectedPerLeagueYear to a research number. Your file's total must reconcile with the research base rates — show the reconciliation in a top-level `"calibrationSummary"` string.
4. Newsworthiness: high-frequency mundane events (births ~200/yr) must carry `"surface": "news"` with a `"userTeamOnly": true` field where league-wide surfacing would be spam. Add that boolean to any event whose league-wide volume would exceed ~20 feed items/season.
5. Severity → surface mapping: career + major ⇒ popup; moderate ⇒ popup only if it carries a decision, else news; minor ⇒ news.
6. Positive events: 15-25% of your file's count where the research supports it (K3 carries most).
7. Valence "contextual" events must include `"contextRule"` (e.g., "record >= .600 → positive framing variant B").
8. IDs unique, snake_case, prefixed k1_/k2_/k3_.
9. Aim for the assigned event count; depth of variants beats padding — variants of one mechanism (star vs depth, offseason vs in-season, first vs repeat) are separate events when their probabilities/effects/headlines differ.
10. DURATION + CARD VISIBILITY (user requirement): every lasting effect must have an explicit duration ([min,max] roll), and every event with availability != none or a >=1-week effect must carry the playerCard block (badge + countdown + detailLine + historyEntry). The player card is where the coach sees "what is wrong with this player and for how long" — no invisible modifiers.
