# FA Drama & Storylines — Design Brief

**Date**: 2026-05-07
**Goal**: Transform the Free Agency phase from a quiet bidding spreadsheet into a dramatic, narrative-driven flagship moment.

## A — Bidding War Drama (7 features)

| # | Feature | Mechanic |
|---|---------|----------|
| A1 | Live Bidding Ticker | Top-of-screen rolling feed: counters, visits, signings as they happen |
| A2 | Frenzy Heat | Per-FA tier (Cool/Yellow/Red/Burning) drives salary inflation -10%/0/+15%/+30% |
| A3 | Visit mechanic | FA visits team facility — 24-48h exclusivity; 1 visit/day, 3/week max |
| A4 | Outbid Alerts | Push-banner with countdown when your offer is countered |
| A5 | Day rhythm | Each FA day: morning offers → afternoon counters → evening lockup |
| A6 | Player Preferences | Hidden tag (Contender/Money/Family/Climate); affects offer ranking |
| A7 | Negotiation Room | Bidding-room sheet with sliders for years/base/SB/guarantees/incentives + agent feedback |

## B — Storylines (8 features)

| # | Feature | Mechanic |
|---|---------|----------|
| B1 | Revenge Tour | Cut players carry grudge flag; +5% performance vs former team for 2 years |
| B2 | Loyalty Veterans | 4+ years on team → -10-15% asking price; let walk → media penalty |
| B3 | Coach Reunions | If your coach previously coached the FA → -10% + +20% loyalty |
| B4 | Hometown Heroes | FA from team's geo region → -5%, hometown press event |
| B5 | Mentor-Protegé | Signing veteran can bring rookie protegé at discount |
| B6 | Holdouts | Sub-market signed players threaten holdouts; 3 resolution paths |
| B7 | Career Milestones | Personal goals (HOF push, comeback) shape signing demands |
| B8 | Community Impact | Per-player civic tag drives city-loyalty + offseason charity events |

## Architecture

### Domain extensions
- `Player`: `hometownState: String?`, `cutByTeamID: UUID?`, `cutAt: Date?`, `loyaltyYears: Int`, `mentorOfPlayerID: UUID?`, `civicTier: CivicTier`
- `CollegeProspect`: same hometown fields
- `Coach`: `previousTeamCoachees: [UUID]` (player IDs coached previously)
- New domain: `FABid`, `FAVisit`, `RevengeTourEvent`, `Holdout`

### Engine layer
- `BiddingHeatEngine` — heat-tier per FA; salary inflation modifier
- `VisitTracker` — schedule visits; exclusivity locks
- `PlayerPreferenceEngine` — generate hidden preferences; rank offers
- `OutbidNotifier` — emits notifications when offer countered
- `RevengeTourEngine` — track grudge flags; performance modifier
- `LoyaltyEngine` — discount calc; let-walk media penalty
- `CoachReunionMatcher` — match coach history to FA list
- `HometownDetector` — geo-match FA to team
- `MentorPairEngine` — known pair lookup
- `HoldoutEngine` — sub-market detection; resolution flow
- `MilestoneTracker` — career stat thresholds
- `CommunityImpactEngine` — civic events

### UI surface
- `FAWeeklyView` — add ticker bar, frenzy heat per FA row, visit indicators
- `BiddingRoomSheet` — modal for negotiation-room (per FA)
- `OutbidAlertBanner` — slide-from-top urgent notification
- `RevengeTourBadge` — flag on player profile
- `HometownTagView` — strip on FA card
- `LoyaltyBadge` — on existing-roster contract view

## Phasing

**Phase 1 (Foundation)**: Domain extensions + engine APIs (no UI yet)
**Phase 2 (Core UX)**: Live Ticker + Frenzy Heat + Outbid Alerts + Day rhythm
**Phase 3 (Strategic)**: Visit mechanic + Player Preferences + Bidding Room
**Phase 4 (Storylines)**: Revenge Tour + Loyalty + Coach Reunion + Hometown
**Phase 5 (Depth)**: Mentor Pairs + Holdouts + Milestones + Community Impact

## Acceptance per phase
- Phase 1: Build verified, schema updated, no crashes
- Phase 2: User sees real-time ticker + per-FA heat tier + outbid countdowns
- Phase 3: Visit-and-sign flow surfaces strategic choices in simulator
- Phase 4: At least 2 storyline events trigger per FA window
- Phase 5: Holdouts + milestones add late-stage drama
