# Phase-Aware Dashboards & Sidebar Timeline — Design Brief

**Date**: 2026-05-07
**Goal**: Dashboard adaptoituu pelin vaiheen mukaan + vasemman sidebarin timeline ryhmittelee vaiheet 5 ylävaiheeseen, joista yksi on uusi **Pre Season** -ryhmä (OTAs + Training Camp + Preseason Games + Roster Cuts).

## 5 ylävaihetta (Phase Groups)

```
[●] Postseason            → proBowl, superBowl
[●] Offseason             → coachingChanges, reviewRoster
[●] Pre-Draft             → combine, freeAgency, proDays, draft
[●] Pre Season ←UUSI      → otas, trainingCamp, preseason, rosterCuts
[●] Regular Season        → regularSeason, tradeDeadline, playoffs
```

## Vasen sidebar — Timeline Group Navigation

Nykyinen `TimelineTasksPanel` näyttää tehtävälistan flat-rakenteella. Päivitetään 2-kerros-rakenteeseen:

```
┌─ POSTSEASON  (collapsible)
│   ✓ Pro Bowl
│   ✓ Super Bowl
├─ OFFSEASON  (collapsible)
│   ✓ Coaching Changes
│   ✓ Roster Review
├─ PRE-DRAFT  (collapsible)
│   ✓ NFL Combine
│   ✓ Free Agency
│   ✓ Pro Days
│   ◉ NFL Draft  ← current sub-phase (gold highlight)
├─ PRE SEASON  (auto-expanded when current)
│   ○ OTAs
│   ○ Training Camp
│   ○ Preseason Games
│   ○ Roster Cuts
└─ REGULAR SEASON
    ○ Regular Season (Wk 1-18)
    ○ Trade Deadline (Wk 9)
    ○ Playoffs
```

Per-group:
- Otsikko gold-värisenä, kompakti
- Status-merkki: ✓ done / ◉ current / ○ upcoming
- Klikkaus auki/kiini, current group auto-expanded
- Sub-phaset = klikattavat row:t jotka ovat suoraan TaskGenerator:in tuomia rivit

## Per Phase Group — Dashboard Composition

### A) Postseason Dashboard
**Hero**: 🌟 Pro Bowl tai 🏆 Super Bowl
**Tiles**:
- **Awards Hub** — Pro Bowlers, All-Pro, MVPs, Rookie of Year
- **Team Accolades** — legacy points earned, season grade
- **End-of-Season Roster Summary** — OVR, average age, cap projection
- **Coach Contracts Expiring** — joiden sopimus loppuu

### B) Offseason Dashboard
**Hero**: 🔄 Offseason Begins
**Tiles**:
- **Coaching Staff** (expiring contracts highlighted)
- **Roster Review** (expirees, cap, key extensions)
- **3-Year Cap Forecast**
- **Offseason Goals**
- **Inbox** (offseason news)

### C) Pre-Draft Dashboard
**Hero**: phase-spesifi (Combine/FA/ProDays/Draft)
**Tiles**:
- **Scouting Hub** — Big Board, Combine, Mock Draft
- **Free Agency** (kun .freeAgency)
- **Pro Days** (kun .proDays)
- **Draft Order**
- **Team Needs**
- **Cap Space**

### D) Pre Season Dashboard ← UUSI
**Hero**: phase-spesifi
- `.otas`: "🏈 OTAs · No-pads · Scheme install" + workload heatmap snapshot
- `.trainingCamp`: "🏋️ Training Camp · Day X / 21" + active battles + top camp grade
- `.preseason`: "🏟️ Preseason · Game X / 3" + snap distribution + surprise breakouts
- `.rosterCuts`: "✂️ Cut Day X / 3 · Y cuts remaining" + cap savings projection

**Tiles** (kaikissa Pre Season -vaiheissa):
- **Training Plan** — focus sliders shortcut
- **Workload Heatmap** — überload-warningit
- **Position Battles** — käynnissä olevat
- **Camp Grades** — top performers
- **Roster Composition** — depth chart 90→53 progress
- **Hard Knocks Feed** — viime tapahtumat

**Tiles** vain `.preseason`:
- **Preseason Games** — 3 ottelua + tulokset

**Tiles** vain `.rosterCuts`:
- **Cut Targets** — engine-suositukset
- **Practice Squad Protection**
- **Waiver Wire** (post-cut)

### E) Regular Season Dashboard
**Hero**: 📅 Week X · Vs OPP_ABBREV (Home/Away) · Streak
**Tiles**:
- **This Week's Game Plan** — game-week prep slider preview
- **Depth Chart**
- **Injury Report** — OUT / Questionable / Probable
- **Opponent Scout** — strengths/weaknesses
- **Standings** — division snapshot
- **Trade Center** (vain .tradeDeadline-aikana, gold-banner)

**Tiles** vain `.tradeDeadline`:
- **Trade Deadline Banner** — "X days remaining"
- **Available Targets** — rumored deals

**Tiles** vain `.playoffs`:
- **Bracket Position**
- **Win-or-go-home Countdown**
- **Playoff Opponent Scout**

## Quick Action Bar (top edge)

Per vaihe, näytetään **3 pikatoiminto-painiketta**:

| Vaihe | Action 1 | Action 2 | Action 3 |
|-------|---------|----------|----------|
| Postseason | View Awards | Coach Renewals | End-of-Season Report |
| Offseason | Coaching Staff | Roster Review | Cap Forecast |
| Pre-Draft | Scouting Hub | Big Board | Mock Draft |
| Pre Season | Training Plan | Position Battles | Camp Grades |
| Regular Season | Game Plan | Depth Chart | Injury Report |

## Implementation Phases

### Phase 1 — Domain: SeasonPhaseGroup
- Uusi enum `SeasonPhaseGroup` (postseason/offseason/preDraft/preSeason/regularSeason)
- `SeasonPhase.group: SeasonPhaseGroup` extension
- `SeasonPhaseGroup.subPhases: [SeasonPhase]` reverse mapping

### Phase 2 — Sidebar Timeline restructure
- `TimelineTasksPanel` → 2-kerros-rakenne
- Per group: kollapsi-otsikko + sub-phaset
- Current group auto-expanded
- Status-icon per sub-phase

### Phase 3 — Phase Group Hero Cards
- Olemassa olevat 11 phase hero-cardia ryhmitellään
- Lisätään pre-season-spesifit hero-rakenteet (workload snapshot, battles, breakouts)

### Phase 4 — Adaptive Tile Grid
- `phaseGroupTiles` switch joka näyttää oikeat tilet per group
- Conditional kunkin tile:n näyttäminen sub-phasen mukaan (esim. Free Agency tile vain `.freeAgency`)

### Phase 5 — Quick Action Bar
- Top-edge 3 pikatoimintoa
- Per phase group erilainen sisältö

## Acceptance per phase

- Phase 1: Build verified, mappings testattu
- Phase 2: Sidebar näyttää 5 ryhmää oikein, current highlight
- Phase 3-4: Dashboard adaptoituu vaiheen mukaan, tilet vaihtuu
- Phase 5: Quick action bar näkyy ja routes oikein
