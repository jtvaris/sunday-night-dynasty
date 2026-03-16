# Sunday Night Dynasty — NFL Football Manager Game Design

**Date:** 2026-03-16
**Platform:** iPadOS (iPad-first)
**Tech Stack:** SwiftUI + SceneKit + Swift Data + Pure Swift Engine
**Bundle ID:** com.brewcrow.dynasty

---

## 1. Core Concept

Dynasty is a deep NFL Football Manager simulation for iPad. The player takes the role of GM or GM + Head Coach, building a football dynasty across multiple seasons. Features realistic NFL mechanics: tactics, roster management, salary cap, draft, scouting, player development, coaching staff, media pressure, and owner expectations.

The player can be fired for poor performance and must find a new job — reputation and track record affect available opportunities.

## 2. Game Loop — NFL Calendar

### Offseason
1. Super Bowl
2. Pro Bowl / Awards
3. Coaching staff changes (hire/fire coordinators, position coaches)
4. NFL Combine
5. Free Agency (Legal Tampering → FA market opens → waves)
6. NFL Draft (7 rounds, real-time trade up/down)
7. OTAs
8. Training Camp
9. Preseason games
10. Roster Cuts (to 53-man roster)

### Regular Season (18 weeks)
- Weekly cycle: Preparation → Game Day → Review
- Trade deadline at week 8
- Bye week per team
- College scouting runs in parallel

### Postseason
- Wild Card → Divisional → Conference Championship → Super Bowl

### Weekly Activities
- Set depth chart and game plan
- Manage injured player statuses
- Make trades (before deadline)
- Monitor scouting reports (college season progressing)
- Handle off-field events (holdouts, media, suspensions)

### Game Day
- Simulate automatically OR participate in play-calling
- Offense and/or defense play-calling selectable independently
- Can switch between simulation and manual mid-game
- Game speed adjustable: 1x, 2x, 4x, instant

## 3. Match Engine

### Play-by-Play Simulation
Each play is simulated in phases:

```
Snap → Pre-snap read →
  Offense: O-line protection / run blocking → QB decision → pass/run/scramble → YAC/tackle
  Defense: Coverage assignment → rush/blitz → reaction → tackle
→ Result (yards, 1st down, turnover, TD, etc.)
```

### Attributes Affecting Each Phase
- Physical attributes (speed, strength, agility)
- Mental attributes (awareness, decision-making, clutch)
- Scheme fit — how well the player fits the team's system

### Dynamic In-Game Layer
- **Momentum** — Big plays shift momentum, affecting the whole team
- **Fatigue** — Accumulates during the game, affects performance. Deep roster is rewarded
- **Morale/Feel** — Feel players react strongly (both ways), steady performers stay consistent
- **Injuries** — Can happen any time, severity varies
- **Drama** — Unexpected events: player arguments, coach challenges, crowd effects (home/away)

### 3D Match View (SceneKit)
- Top-down camera angle, full field visible
- Simple player models (color-coded by team, numbers visible)
- Formations and routes clearly visible
- Game speed adjustable (1x, 2x, 4x, instant)
- Pause and make play-calls at any time

## 4. Player Model

### Attributes (1-99 scale)

**Physical:** Speed, Acceleration, Strength, Agility, Stamina, Durability

**Mental:** Awareness, Decision Making, Clutch, Work Ethic, Coachability, Leadership

**Position-specific examples:**
- QB: Arm Strength, Accuracy (Short/Mid/Deep), Pocket Presence, Scrambling
- WR: Route Running, Catching, Release, Spectacular Catch
- OL: Run Block, Pass Block, Pull, Anchor
- DL: Pass Rush, Block Shedding, Power Moves, Finesse Moves
- CB: Man Coverage, Zone Coverage, Press, Ball Skills
- (Full list per position to be defined in implementation)

### Personality (permanent, rarely changes)
- **Archetype:** Team Leader, Lone Wolf, Feel Player, Steady Performer, Drama Queen, Quiet Professional, Mentor, etc.
- **Motivation:** Money, Winning, Stats, Loyalty, Fame
- **Work Ethic:** Affects development speed
- **Coachability:** How well they respond to coaching
- **Locker Room Impact:** Positive/negative/neutral effect on others

### Player Development
- Age curve (peak varies by position: QB 28-35, RB 24-28, WR 26-31, etc.)
- Playing time + practice + coaching quality → development points
- Personality modulates: high work ethic + good coachability = fast development
- Veteran mentor can accelerate young player development (leadership attribute)
- Injury history can permanently lower Durability
- Regression with age — physical attributes first, mental attributes last

### Potential (hidden)
- Each player has a "true" potential that is not directly visible
- Scouting reveals an estimate of potential (can be wrong)
- Only realized under the right conditions (coaching fit, personality, playing time)

## 5. Scouting and Draft

### Scout Team
- Scouting budget (limited)
- Hire scouts with their own attributes:
  - **Position Specialization** (QB scout, OL scout, etc.)
  - **Accuracy** — how close to true ratings they get
  - **Personality Read** — ability to assess character and work ethic
  - **Potential Read** — ability to see ceiling vs. floor
- Scouts develop with experience

### Scouting Process (follows real NFL calendar)

**Fall (college season):**
- Assign scouts to watch college games
- Reports arrive weekly, improve as season progresses
- Regional scouts vs. national scouts

**January-February:**
- Senior Bowl, shrine games — closer looks
- Preliminary big boards

**Combine (February-March):**
- 40 yard dash, bench press, shuttle, etc. — objective data
- Combine results can mislead (combine warrior vs. game-smart player)

**Pro Days:**
- Team-specific visits, more detailed information

**Interviews:**
- Reveal personality, motivation, coachability
- Good personality read scout gets more accurate picture

**Draft Week:**
- Final big board
- Other teams make trade offers for picks in real-time

### Draft (7 rounds)
- AI teams draft based on their needs and big boards
- Trade up/down in real-time — AI can offer you deals or you can make offers
- Future pick trades (next years' selections)
- Tension: is the scout's assessment correct? Bust or steal?

### Draft Risk
- Scouts can be wrong — accuracy attribute determines error margin
- Player's "true" attributes are revealed gradually over first seasons
- Combine results can over-inflate/deflate a player (hype)
- Personality issues don't always show before the draft

## 6. Media, Owner, and Pressure

### Weekly News / Headlines
Dynamic news feed reacting to game events:
- Pre-draft speculation and mock drafts
- Draft grades ("Grade: A- / F — Experts react to picks")
- In-season: player performances, injuries, scandals
- Bust/steal tracking ("2025 1st rounder struggling — was it a reach?")
- Trade rumors, free agency speculation
- Coach hot seat reports

### Media Market (per team)

| Market Size | Examples | Effect |
|---|---|---|
| Small | Green Bay, Jacksonville | Less media pressure, patient fans, easier to rebuild |
| Medium | Denver, Baltimore | Moderate pressure, balanced expectations |
| Large | New York, Dallas, LA | Constant pressure, every loss is a crisis, stronger FA attraction |

### Owner
Each team has an owner with a profile:
- **Patience** — how many bad seasons before firing
- **Spending Willingness** — scouting budget, facilities, coaching budget
- **Meddling** — interferes with decisions ("owner wants you to draft a QB")
- **Win Now vs. Rebuild** — accepts long-term projects or not

Owner satisfaction is visible (green/yellow/red). If it drops too low → **fired**.

After being fired:
- Apply for new jobs — reputation affects offers
- Bad track record = only bad teams offer
- Good legacy = pick where you go

### Media Effects
- Player morale (especially Fame-motivated and Drama Queen types)
- Free agent attractiveness
- Owner satisfaction
- Fan patience

## 7. Off-Field Events and Drama

### Offseason Events

**Contract disputes:**
- Holdout — player doesn't report to camp, wants new deal
- Franchise tag unhappiness
- "Wants out" — player publicly requests trade (media firestorm)

**Player drama:**
- Suspensions (league discipline)
- Arrests / legal issues
- Social media incidents
- Holdout from camp (personal reasons)
- Retirement speculation (veterans)
- Player publishes podcast criticizing coaching

**Positive drama:**
- Player wins Man of the Year → morale boost
- Veteran announces return → leadership effect
- Players organize voluntary workouts → chemistry bonus
- Rookie impresses at camp → hype

**Coaching drama:**
- Coordinator interviewed for HC job elsewhere
- Coaching staff conflicts
- Position coach gets college offer
- Former coach publicly criticizes

**Injuries:**
- Offseason surgeries, rehab progress
- "Ahead of schedule" / "setback" news
- Freak injury at camp

### How Events Are Generated
- Player personality determines probability (Drama Queen → more events)
- Team success affects (bad season → more negative drama)
- Contract situation affects (underpaid player → holdout risk)
- Media market amplifies or dampens impact

### Player (GM/HC) Decisions
- Holdout: pay up / counsel / trade / wait it out
- Suspension: support publicly / distance yourself / wait and see
- Conflicts: pick a side / mediate / ignore
- Every choice has consequences → locker room, media, owner

## 8. Coaching Staff

### Hierarchy

```
Head Coach (player themselves or hired)
├── Offensive Coordinator
│   ├── QB Coach
│   ├── RB Coach
│   ├── WR Coach
│   └── OL Coach
├── Defensive Coordinator
│   ├── DL Coach
│   ├── LB Coach
│   └── DB Coach
├── Special Teams Coordinator
└── Strength & Conditioning Coach
```

### Coach Attributes
- **Scheme** — West Coast, Air Raid, Spread, Power Run, Shanahan / 3-4, 4-3, Cover 3, Press Man, etc.
- **Play Calling** — Quality of in-game decisions (AI play-calling)
- **Player Development** — How much they improve player growth
- **Recruiting/Reputation** — Affects FA attractiveness
- **Personality** — Relationship with players, other coaches, media
- **Adaptability** — Ability to adjust scheme to roster

### Coaching Fit
- Player style matches scheme → development bonus, better performance
- Mismatch → suboptimal development, player dissatisfaction
- Example: mobile QB + pocket passer scheme = bad fit

### Coach Careers
- Coaches develop over years
- Successful coordinators get HC interview requests → you may lose them
- Coaching tree — coaches who left your staff are remembered
- Hire/fire freely, but turnover affects team stability
- Hiring: interview process, coach comparison

### GM Mode (not HC)
- Hire a Head Coach with their own preferences
- HC may disagree on draft picks or roster decisions
- Good HC-GM relationship = bonus, bad = drama and media pressure

## 9. Contracts and Salary Cap

### Two Modes (chosen at career start, cannot change)

### Simple Mode
- Salary cap (fixed annual budget, grows yearly)
- Contracts: length (1-5 years) + annual salary
- Free agency: bidding war
- Franchise tag (1 player/year)
- Trades: player + picks

### Realistic Mode
Everything in Simple Mode plus:

**Contract structure:**
- Base Salary
- Signing Bonus (prorated cap hit across contract years)
- Guaranteed Money (fully / partially guaranteed)
- Roster Bonus, Workout Bonus
- Incentives (LTBE / NLTBE)
- Option Years
- Void Years (push cap hit to future)
- No-Trade Clause, No-Franchise Tag Clause

**Cap Management:**
- Dead Cap (remaining guaranteed money of cut player)
- Cap Rollover (unused cap carries to next year)
- Restructure (convert base salary to signing bonus → frees cap now, costs later)
- Post-June 1 Cut (dead cap split across two years)
- Cap Casualties — sometimes must cut good players

**Free Agency:**
- Legal Tampering Period
- FA market opens → frantic first wave
- Compensatory picks (based on lost FA players)

### Both Modes
- AI teams follow the same rules
- Player motivation affects negotiations (Money vs. Winning vs. Loyalty)
- Agent personality — tough negotiators vs. fair dealers

## 10. Technical Architecture

### Tech Stack
| Layer | Technology |
|---|---|
| UI | SwiftUI (menus, lists, navigation) |
| 3D Match View | SceneKit (field, players, animations) |
| Data Persistence | Swift Data (save games) |
| Game Engine | Pure Swift (simulation, no framework dependencies) |
| Target | iPadOS (iPad-first, possible iPhone later) |

### Architecture Layers

```
┌─────────────────────────────────┐
│  UI Layer (SwiftUI + SceneKit)  │
├─────────────────────────────────┤
│  Presentation (ViewModels)      │
├─────────────────────────────────┤
│  Game Logic (Use Cases)         │
│  - SimulationEngine             │
│  - DraftEngine                  │
│  - ScoutingEngine               │
│  - ContractEngine               │
│  - PlayerDevelopmentEngine      │
│  - MediaEngine                  │
│  - EventEngine                  │
├─────────────────────────────────┤
│  Domain (Models)                │
│  - Player, Team, Coach, Owner   │
│  - Contract, DraftPick, Scout   │
│  - Season, Game, Play           │
├─────────────────────────────────┤
│  Data Layer (Swift Data)        │
│  - Save/Load                    │
│  - Import/Export (roster packs) │
└─────────────────────────────────┘
```

### Roster Import/Export
- JSON-based format
- Contains players, teams, names, attributes
- Default data: randomized players
- Development uses real data, release uses generic
- Community can create and share roster packs

## 11. League Structure

- 32 teams, real NFL divisions (AFC/NFC, 4 divisions each)
- All names, logos, and player names are customizable
- Default: generic/randomized
- Import system for community roster packs
- Full NFL schedule: 18-week regular season, playoffs, Super Bowl
