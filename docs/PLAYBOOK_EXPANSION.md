# Playbook Expansion — Canonical Catalog

Single source for the playbook expansion wave. Implementation agents build from **this file**;
nothing here invents an engine mechanic that the recon did not find. Every number below is
expressed in the existing vocabulary: `SimulatorHint` scalars, `DefensivePackage` dimension
modifiers, `RouteSpec.Waypoint` yards, `OffenseTendency` archetypes, `PlayType`.

Target files (absolute):
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty/Domain/Enums/PlayCall.swift`
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty/UI/Match/RouteSpec.swift`
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty/UI/Match/PlayChoreographer.swift`
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty/UI/Match/PlayDiagramView.swift`
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty/UI/Match/CoachedGameView.swift`
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty/Engine/Match/AdaptiveOpponentAI.swift`
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty/Engine/Match/CoordinatorPersona.swift`
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty/Engine/Match/LiveGameEngine.swift`
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty/Engine/Match/MatchupResolver.swift`
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty/Engine/Simulation/PlaySimulator.swift`

---

## 0. Ground rules (read first)

1. **Never change an existing case's `rawValue`.** `OffensivePlayCall` is `Codable` and its
   rawValue is persisted in `Career.weeklyPracticePlayRaw` and `Career.bonusInstalledPlaysRaw`.
   Renaming an existing display name silently drops a user's practiced/installed play. New
   rawValues become save data the moment they ship — pick them once.
2. **The only per-play engine surface is `SimulatorHint`** — six scalars
   (`passDepth`, `runGapBonus`, `blitzPickupBonus`, `yacMultiplier`, `isPlayAction`, `edgeFactor`).
   "Risk profile", "target profile" and "protection" below are **design intent expressed through
   those six**, not new fields. Do not go looking for an INT knob or a personnel field; there is none.
3. **New tabs are a one-line UI change.** `CoachedGameView.swift:1412`
   `private let categories = [...]` plus `shortCategoryName(_:)` at L1712. This catalog adds three:
   `"Screen"`, `"Play Action"`, `"RPO"` → 8 tabs total. `shortCategoryName` maps
   `"Short Pass"→"Short"`, `"Medium Pass"→"Medium"`, `"Deep Pass"→"Deep"` and otherwise returns
   the category verbatim; add `"Play Action"→"PA"` so eight capsules still fit (`"Run"`,
   `"Screen"`, `"RPO"`, `"Special"` are already short enough to fall through the `default:`).
4. **Signature plays get NO new familiarity mechanic.** The recon shows the real bust
   (`PlaySimulator.familiarityBustChance`, L3939) does not read the call, and the −15
   out-of-playbook penalty in `MatchupResolver.bustRoll` (L551) is cosmetic (drives an `Event`
   string, never yards). Scheme identity is therefore expressed by exactly three levers:
   (a) exclusive membership in `OffensivePlayCall.schemes`, (b) the hint profile,
   (c) presence in the OC's `signaturePool` / `recommended*Call` order. That is enough — a
   non-installed play is dimmed, ordered last, and picked last by the AI.
   *Optional, cosmetic-only:* mirror the existing −15 with a `+10` in `bustRoll` when the call is a
   signature of the active scheme. Flagged OPTIONAL because it moves feed text, not outcomes.
5. **Quick sim is untouched.** `GameSimulator.simulate` passes `offensiveCall: nil` everywhere
   except two hardcoded sites (`GameSimulator.swift:682` `.playActionDeep`, `:771` `.slant`).
   A pure additive wave therefore **cannot** move season-sim balance and needs no harness re-gate.
   Coached-game balance *can* move, because `LiveGameEngine`'s AI picks from these pools —
   see §3 migration.

---

## 1a. New offensive plays — 34 cases

Columns: `runGap` = `runGapBonus`, `pickup` = `blitzPickupBonus`, `yac` = `yacMultiplier`,
`edge` = `edgeFactor`, `PA` = `isPlayAction`. `depth` = `passDepth` (`—` = nil, run resolves it).
`fam` = `FormationFamily`. `tend` = `AdaptiveOpponentAI.OffenseTendency`.

### RUN tab — 9 new (existing 8 stay; `.screen` moves to the Screen tab)

| case | display | fam | type | depth | runGap | pickup | yac | edge | tend | blurb |
|---|---|---|---|---|---|---|---|---|---|---|
| `insideZone` | Inside Zone | `.iForm` | run | — | +0.14 | 0 | 1.05 | 0 | insideRun | "Press the front side, one cut, get north." |
| `wideZone` | Wide Zone | `.stretch` | run | — | −0.04 | 0 | 1.35 | 0.95 | outsideRun | "Stretch the whole front, bend it back if they overrun." |
| `duo` | Duo | `.iForm` | run | — | +0.20 | 0 | 0.95 | 0 | insideRun | "Double team everything, back reads the backer." |
| `power` | Power O | `.iForm` | run | — | +0.22 | −0.05 | 1.00 | 0 | insideRun | "Down block, kick out, guard leads through the hole." |
| `trap` | Trap | `.iForm` | run | — | +0.18 | 0 | 1.20 | 0 | insideRun | "Let him through, then bury him with the backside guard." |
| `zoneRead` | Zone Read | `.pistol` | run | — | +0.08 | +0.10 | 1.25 | 0.45 | insideRun | "Read the end — give it or keep it, he can't have both." |
| `qbDraw` | QB Draw | `.pistol` | run | — | +0.06 | +0.15 | 1.30 | 0.20 | insideRun | "Drop back, then run it right at the vacated middle." |
| `endAround` | End Around | `.stretch` | run | — | −0.18 | +0.05 | 1.55 | 1.25 | outsideRun | "Receiver comes back the other way at full speed." |
| `speedOption` | Speed Option | `.pistol` | run | — | −0.12 | 0 | 1.40 | 1.15 | outsideRun | "Attack the edge and make the end wrong." |

Risk/target notes: `duo`/`power`/`trap` are the short-yardage hammers (high `runGap`, low `yac` →
consistent, rarely explosive). `endAround`/`speedOption` are the boom-or-bust perimeter calls
(`edge ≥ 1.15` × negative `runGap` → the edge-crease gate at `PlaySimulator.swift:1468` decides
everything). `zoneRead`/`qbDraw` carry `pickup > 0` because the read/vacated-rush is the
protection story.

### SCREEN tab — 3 new (+ existing `.screen`, re-categorised, rawValue untouched)

**Decision:** new screens are `isPass == true`, `isRun == false`. Do **not** repeat the `.screen`
legacy wart (`isRun` true, forced to `.pass` at `PlaySimulator.swift:258–262`). Consequence:
they survive the long-yardage filter in `AdaptiveOpponentAI.offensiveCounter`
(`pool.removeAll { $0.isRun && $0 != .screen }`) with no special case.

| case | display | fam | type | depth | runGap | pickup | yac | edge | tend | blurb |
|---|---|---|---|---|---|---|---|---|---|---|
| `bubbleScreen` | Bubble Screen | `.quick` | screen (pass) | short | 0 | +0.30 | 1.70 | 0 | screen | "Ball out now — let the slot run behind his blockers." |
| `tunnelScreen` | Tunnel Screen | `.quick` | screen (pass) | short | 0 | +0.25 | 1.85 | 0 | screen | "Bring him back inside behind a wall of blockers." |
| `slipScreen` | Slip Screen | `.backfield` | screen (pass) | short | 0 | +0.22 | 1.75 | 0 | screen | "Back slips out of protection into open grass." |

(`.screen` keeps its existing hint: short / +0.20 pickup / 1.8 yac. Only its `category` string
changes from `"Run"` to `"Screen"`.)

### SHORT PASS tab — 5 new

| case | display | fam | type | depth | runGap | pickup | yac | edge | tend | blurb |
|---|---|---|---|---|---|---|---|---|---|---|
| `spot` | Spot | `.quick` | pass | short | 0 | +0.22 | 0.95 | 0 | shortPass | "Corner, flat, and a man sitting in the hole." |
| `snag` | Snag | `.quick` | pass | short | 0 | +0.20 | 1.00 | 0 | shortPass | "Slide inside, pull the flat defender two ways." |
| `shallowCross` | Shallow Cross | `.quick` | pass | short | 0 | +0.12 | 1.45 | 0 | shortPass | "Run him flat across the field and let him go." |
| `angle` | Angle Route | `.quick` | pass | short | 0 | +0.18 | 1.35 | 0 | shortPass | "Back sells the flat, then snaps back inside the backer." |
| `fade` | Back Pylon Fade | `.quick` | pass | short | 0 | +0.10 | 0.60 | 0 | shortPass | "Put it where only he can get it, back corner." |

Risk/target: `fade` is the red-zone isolation throw — low `yac` and low `pickup` mean it lives or
dies on the completion roll (WR-vs-CB via `coverageManWeight`); it is the one short call that
is *not* a blitz beater. `angle`/`shallowCross` are the man-coverage answers (see `goodAgainst`).

### MEDIUM PASS tab — 5 new

| case | display | fam | type | depth | runGap | pickup | yac | edge | tend | blurb |
|---|---|---|---|---|---|---|---|---|---|---|
| `levels` | Levels | `.baseGun` | pass | medium | 0 | 0 | 1.05 | 0 | mediumPass | "Two in-cuts at two depths — pick a level." |
| `yCross` | Y-Cross | `.crossSet` | pass | medium | 0 | −0.05 | 1.30 | 0 | mediumPass | "Tight end runs the whole field, everything else clears." |
| `dagger` | Dagger | `.baseGun` | pass | medium | 0 | −0.08 | 1.10 | 0 | mediumPass | "Seam clears the hook, dig comes in behind it." |
| `sail` | Sail | `.baseGun` | pass | medium | 0 | +0.05 | 1.00 | 0 | mediumPass | "Three-level stretch to the boundary." |
| `smash` | Smash | `.baseGun` | pass | medium | 0 | 0 | 0.90 | 0 | mediumPass | "Hitch under, corner over — high-low the flat corner." |

### DEEP PASS tab — 3 new

| case | display | fam | type | depth | runGap | pickup | yac | edge | tend | blurb |
|---|---|---|---|---|---|---|---|---|---|---|
| `fourVerts` | Four Verticals | `.spreadDeep` | pass | deep | 0 | −0.18 | 1.05 | 0 | deepPass | "Four straight lines. Somebody wins one." |
| `sluggo` | Sluggo | `.spreadDeep` | pass | deep | 0 | −0.20 | 1.15 | 0 | deepPass | "Sell the slant all day, then run right past him." |
| `backShoulder` | Back Shoulder | `.spreadDeep` | pass | deep | 0 | −0.12 | 0.55 | 0 | deepPass | "Throw it where the corner isn't — he comes back to it." |

Risk/target: `sluggo` is the double move — the most negative `pickup` in the wave next to `bomb`
(the hold time is the cost). `backShoulder` is the low-YAC, contested deep answer to press man
(the `manToMan && short` press branch never fires on it; it wins on the raw completion roll).

### PLAY ACTION tab — 3 new (+ existing `.playActionDeep`, re-categorised)

`.playActionDeep`'s `category` moves `"Deep Pass"` → `"Play Action"`, and its `formationFamily`
moves `.spreadDeep` → `.playAction`. rawValue untouched. Every play here sets `isPlayAction: true`
(gates the box-bite roll at `PlaySimulator.swift:509` and the keyed-PA punish at L710/L952).

| case | display | fam | type | depth | runGap | pickup | yac | edge | PA | tend | blurb |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `paBoot` | PA Boot | `.playAction` | PA pass | medium | 0 | +0.15 | 1.25 | 0 | ✓ | playAction | "Fake it, roll away from the pressure, take what's there." |
| `paCross` | PA Deep Cross | `.playAction` | PA pass | medium | 0 | −0.10 | 1.35 | 0 | ✓ | playAction | "Suck the backers up, run the crosser behind them." |
| `paGlance` | PA Glance | `.playAction` | PA pass | short | 0 | +0.10 | 1.20 | 0 | ✓ | playAction | "One-step fake, glance route off the safety's eyes." |

`paBoot` is the only PA call with a **positive** `pickup` — the rollout is the protection. That
distinction is the whole point of having it next to `playActionDeep` (−0.15).

### RPO tab — 4 new

**RPO representation — read this before implementing.**
The engine has no give/pull mechanic. Two options; ship **A** unless the balance owner asks for B.

- **Option A (default, zero engine risk):** every RPO case is `isPass == true`, `passDepth: .short`,
  high `pickup` (the ball is out before the read defender can matter), `tend = .shortPass`.
  The "give" side of the RPO is represented by the scheme's zone runs (`insideZone`, `zoneRead`),
  which sit in the same `.pistol` formation family — so the *audible strip itself* is the RPO:
  the coach checks `rpoBubble → zoneRead` at the line. Numbers below are Option A.
- **Option B (optional extension, one field + one branch):** add `var rpoGiveChance: Double = 0`
  to `SimulatorHint` and one branch in `PlaySimulator.playType(for:)` (which already special-cases
  `.screen` at L258): `if hint.rpoGiveChance > 0, Double.random(...) < hint.rpoGiveChance { return .run }`.
  Suggested give chances: bubble 0.55, slant 0.50, stick 0.45, pop 0.40. This puts RNG into a
  previously deterministic function — verify `forcedPlayType` precedence (L106) and the two-point
  path before adopting.

| case | display | fam | type | depth | runGap | pickup | yac | edge | tend | blurb |
|---|---|---|---|---|---|---|---|---|---|---|
| `rpoBubble` | RPO Bubble | `.pistol` | RPO (pass) | short | +0.10 | +0.28 | 1.55 | 0 | shortPass | "Count the box — if they're light, the bubble is free." |
| `rpoSlant` | RPO Slant | `.pistol` | RPO (pass) | short | +0.10 | +0.25 | 1.25 | 0 | shortPass | "Read the backer: he steps up, the slant is open." |
| `rpoStick` | RPO Stick | `.pistol` | RPO (pass) | short | +0.10 | +0.24 | 1.00 | 0 | shortPass | "Handoff or stick route — the flat defender decides." |
| `rpoPop` | RPO Pop Pass | `.pistol` | RPO (pass) | short | +0.10 | +0.20 | 1.30 | 0 | shortPass | "Sell the dive, pop it over the crashing linebacker." |

`runGapBonus: +0.10` is inert on the pass path (only read at `PlaySimulator.swift:1415`) — it is
there so Option B, and the two-point path (`runGapBonus*0.3` at L2201), behave sanely if adopted.

### SPECIAL tab — 2 new

| case | display | fam | type | depth | runGap | pickup | yac | edge | tend | blurb |
|---|---|---|---|---|---|---|---|---|---|---|
| `tushPush` | Push Sneak | `.iForm` | run | — | +0.38 | 0 | 0.55 | 0 | insideRun | "Everybody push. One yard, no drama." |
| `hailMary` | Hail Mary | `.spreadDeep` | pass | deep | 0 | −0.25 | 1.00 | 0 | deepPass | "Everybody to the end zone. Throw it up." |

`tushPush` is deliberately the highest `runGap` in the game (`qbSneak` = 0.30) with the lowest
`yac` — a near-guaranteed yard that can never break. Situational gating (show it only on
3rd/4th-and-1) is a UI concern, not an engine one.

---

## 1b. New defensive calls

Two layers, matching the recon: **dimension cases** (`DefensivePlayCall`, what the sim actually
reads via `DefensivePackage`) and **named calls** (`DefensiveCall`, what the call sheet sells).

### New `DefensivePlayCall` dimension cases — 7

| case | display | dimension | `coverageModifier` | `pressureModifier` | `runStopModifier` | `deepCoverageModifier` | `shortCoverageModifier` |
|---|---|---|---|---|---|---|---|
| `tampa2` | Tampa 2 | Coverage | +0.07 | 0.0 | 0.0 | +0.05 | −0.03 |
| `cover6` | Cover 6 | Coverage | +0.09 | 0.0 | 0.0 | +0.02 | 0.0 |
| `cover0` | Cover 0 | Coverage | +0.14 | +0.04 | +0.03 | −0.12 | 0.0 |
| `fireZone` | Fire Zone | Blitz | −0.01 | +0.07 | +0.01 | 0 | 0 |
| `simPressure` | Sim Pressure | Blitz | +0.01 | +0.05 | −0.01 | 0 | 0 |
| `odd34` | 3-4 Front | Front | +0.01 | +0.03 | +0.06 | 0 | 0 |
| `bigNickel` | Big Nickel | Front | +0.06 | −0.01 | −0.02 | 0 | 0 |

Design logic in the recon's terms: `tampa2` buys the deep middle (`deepCoverageModifier +0.05`,
the MLB carrying the pipe) and pays for it in the flats (`short −0.03`). `cover0` is the mirror
of `prevent`: tightest raw coverage in the game, worst deep shading. `fireZone` is the "sound"
5-man pressure (pressure without the coverage tax that `doubleAGap`/`allOutBlitz` pay);
`simPressure` is the creeper — rushes four, so it buys pressure with almost no coverage cost,
which is exactly why it must stay small (+0.05).

**Man-family gates that must be extended (see §3):** `cover0` is man coverage, but three sites
key on `coverage == .manToMan` by identity. `tampa2`/`cover6` are zone and need no gate change.

### New `DefensiveCall` named calls — 14

| case | display | tab | package (coverage / blitz / front) | blurb |
|---|---|---|---|---|
| `tampa2` | Tampa 2 | Coverage | `tampa2` / `noBlitz` / `base` | "Two deep, and the Mike runs the pipe." |
| `cover6` | Cover 6 | Coverage | `cover6` / `noBlitz` / `nickel` | "Quarters to the field, half to the boundary." |
| `cloud2` | Cloud 2 | Coverage | `cover2` / `noBlitz` / `bigNickel` | "Corner caps the flat, safety takes the deep half." |
| `cover1Robber` | Cover 1 Robber | Man | `cover1` / `noBlitz` / `bigNickel` | "Man everywhere, one thief sitting on the dig." |
| `twoManPress` | 2-Man Press | Man | `manToMan` / `noBlitz` / `bigNickel` | "Jam them at the line, two safeties over the top." |
| `cover0` | Cover 0 | Pressure | `cover0` / `allOutBlitz` / `nickel` | "Zero help. Everybody covers, everybody else comes." |
| `fireZone` | Fire Zone | Pressure | `cover3` / `fireZone` / `base` | "Five come, a lineman drops — three deep behind it." |
| `simPressure` | Sim Pressure | Pressure | `cover4` / `simPressure` / `nickel` | "Show the house, rush four, keep the coverage whole." |
| `creeper` | Nickel Creeper | Pressure | `cover3` / `simPressure` / `bigNickel` | "Backer creeps late, the end drops out behind him." |
| `edgeDog` | Edge Dog | Pressure | `cover1` / `lbBlitz` / `nickel` | "Both edges dog it — squeeze the pocket from outside." |
| `overload` | Overload | Pressure | `manToMan` / `safetyBlitz` / `bigNickel` | "Load one side. Make the back block a safety." |
| `dimeFire` | Dime Fire | Pressure | `cover2` / `dbBlitz` / `dime` | "Six DBs, and one of them is coming." |
| `base34` | 3-4 Base | Packages | `cover3` / `noBlitz` / `odd34` | "Two-gap the odd front, backers run free." |
| `bigNickel` | Big Nickel | Packages | `cover4` / `noBlitz` / `bigNickel` | "Third safety in — cover the tight end, still play the run." |

Notes: `bearFront` already **is** the 46, so no separate 46 call. `quarters` / `cover4Match`
already cover quarters + match. `cornerBlitz` already covers the corner blitz.

---

## 2. Per-scheme playbooks

**These lists are authoritative.** The implementation inverts them into
`OffensivePlayCall.schemes` / `DefensiveCall.schemes` (a play appears in a scheme's array iff the
scheme lists it). Existing membership arrays are **replaced**, not extended — the current arrays
are near-universal and give every scheme the same call sheet, which is the problem this wave fixes.
Nothing is lost: a non-installed play is still fully callable at 0.45 opacity with the
"Practice this week" context menu (`CoachedGameView.swift:1785`).

`qbSneak`, `spike`, `kneel` stay `OffensiveScheme.allCases`.
`cover3Base`, `prevent`, `nickelPackage`, `dimePackage`, `goalLineD` stay `DefensiveScheme.allCases`.

**"Call-tendency weights"** below are the OC's ordered preference lists — they slot directly into
`LiveGameEngine.recommendedRunCall` (L2286) and `recommendedPassCall` (L2302), and into
`OCPersona.signaturePool` (`CoordinatorPersona.swift:246`). `passBias` is the existing
`offensiveSchemePassBias` constant (unchanged — do not retune it in this wave).

---

### `westCoast` — rhythm quick game + YAC · passBias +0.08 · persona `.westCoast`

**Signature (4):** `spot` · `angle` · `shallowCross` · `slipScreen`

**Install (17):** insideZone, draw, trap · screen, slipScreen · slant, quickOut, flat, drag, stick,
spot, snag, angle, shallowCross · curl, levels, sail · paBoot

| OC order | plays |
|---|---|
| run (dist ≤ 1) | qbSneak, insideZone, draw |
| run (normal) | insideZone, draw, trap |
| pass short | slant, quickOut, spot, angle, drag, stick, flat, shallowCross |
| pass medium | curl, levels, sail, snag |
| pass deep | paBoot, sail |
| signature pool (share 0.30) | dist ≤ 2 → slant, quickOut, flat, spot; else → slant, spot, angle, shallowCross, drag, stick, slipScreen |

Identity check: no `fourVerts`, no `bomb`, no `sluggo`. West Coast never gets a true deep tab —
its "deep" order collapses to `paBoot`, which is exactly the Walsh answer.

---

### `airRaid` — verts / mesh / empty · passBias +0.15 · persona `.airRaid`

**Signature (4):** `fourVerts` · `yCross` · `sluggo` · `snag`

**Install (17):** draw, qbDraw · bubbleScreen, tunnelScreen · mesh, hitch, stick, snag,
shallowCross · dig, dagger, yCross, smash · fourVerts, goRoute, post, sluggo

| OC order | plays |
|---|---|
| run (dist ≤ 1) | qbSneak, qbDraw, draw |
| run (normal) | draw, qbDraw |
| pass short | mesh, snag, stick, hitch, shallowCross |
| pass medium | dig, dagger, yCross, smash |
| pass deep | fourVerts, post, goRoute, sluggo |
| signature pool (share 0.32) | dist ≤ 2 → mesh, snag, stick; else → fourVerts, yCross, dagger, sluggo, mesh, post |

---

### `spread` — space + read game · passBias +0.05 · persona `.airRaid`|`.balanced`

**Signature (4):** `zoneRead` · `rpoBubble` · `bubbleScreen` · `fourVerts`

**Install (17):** insideZone, wideZone, zoneRead, jetSweep, qbDraw · bubbleScreen, tunnelScreen ·
rpoBubble, rpoSlant, rpoStick · slant, mesh, spot · seam, smash · fourVerts, post

| OC order | plays |
|---|---|
| run (dist ≤ 1) | qbSneak, zoneRead, insideZone |
| run (normal) | zoneRead, insideZone, wideZone, jetSweep, qbDraw |
| pass short | rpoBubble, slant, bubbleScreen, spot, mesh, rpoSlant |
| pass medium | seam, smash |
| pass deep | fourVerts, post |
| signature pool (share 0.30) | dist ≤ 2 → rpoStick, rpoSlant, bubbleScreen; else → zoneRead, rpoBubble, bubbleScreen, fourVerts, jetSweep |

---

### `powerRun` — gap-scheme ground identity · passBias −0.15 · persona `.groundAndPound`

**Signature (4):** `power` · `duo` · `trap` · `tushPush`

**Install (16):** power, duo, trap, counter, dive, insideRun, toss, tushPush · screen ·
stick, flat, fade · comeback, smash · playActionDeep, paCross

| OC order | plays |
|---|---|
| run (dist ≤ 1) | tushPush, qbSneak, dive, duo |
| run (normal) | power, duo, insideRun, counter, trap, toss |
| pass short | stick, flat, fade |
| pass medium | comeback, smash |
| pass deep | playActionDeep, paCross |
| signature pool (share 0.38) | dist ≤ 2 → tushPush, dive, duo, power; dist < 8 → power, duo, trap, counter, insideRun; else → [] |

---

### `shanahan` — outside zone + boots + PA crossers · passBias −0.10 · persona `.balanced`|`.groundAndPound`

**Signature (4):** `wideZone` · `paBoot` · `paCross` · `endAround`

**Install (17):** wideZone, insideZone, outsideRun, counter, jetSweep, endAround ·
screen, slipScreen · flat, drag · yCross, sail, dagger · post ·
paBoot, paCross, playActionDeep

| OC order | plays |
|---|---|
| run (dist ≤ 1) | qbSneak, insideZone, wideZone |
| run (normal) | wideZone, insideZone, counter, outsideRun, jetSweep, endAround |
| pass short | flat, drag, slipScreen |
| pass medium | paBoot, yCross, sail, dagger |
| pass deep | paCross, playActionDeep, post |
| signature pool (share 0.34) | dist ≤ 2 → wideZone, insideZone; dist < 8 → wideZone, counter, endAround, paBoot; else → paCross, paBoot, yCross |

The wide-zone/boot marriage is the whole identity: `wideZone` (`edge 0.95`, `yac 1.35`) sells the
flow, `paBoot` (`isPlayAction`, `pickup +0.15`) punishes the bite. Both live in different formation
families on purpose — the coach cannot audible between them, he has to call them.

---

### `proPassing` — dropback pro-style, full-field reads · passBias +0.10 · persona `.balanced`|`.westCoast`

**Signature (4):** `dagger` · `levels` · `backShoulder` · `comeback`

**Install (17):** insideRun, insideZone, power, draw · screen · hitch, quickOut, stick ·
curl, dig, comeback, levels, dagger · goRoute, backShoulder, post, flood

| OC order | plays |
|---|---|
| run (dist ≤ 1) | qbSneak, insideRun, power |
| run (normal) | insideRun, insideZone, power, draw |
| pass short | hitch, quickOut, stick |
| pass medium | curl, dig, comeback, levels, dagger |
| pass deep | post, goRoute, backShoulder, flood |
| signature pool (share 0.28) | dist ≤ 2 → hitch, stick, quickOut; else → dagger, levels, dig, comeback, backShoulder |

---

### `rpo` — conflict the second level · passBias 0.00 · persona `.westCoast`|`.balanced`

**Signature (4):** `rpoPop` · `rpoStick` · `rpoSlant` · `zoneRead`

**Install (17):** insideZone, wideZone, zoneRead, qbDraw, jetSweep · rpoBubble, rpoSlant,
rpoStick, rpoPop · bubbleScreen, tunnelScreen · slant, drag, spot · seam, smash · post

| OC order | plays |
|---|---|
| run (dist ≤ 1) | qbSneak, zoneRead, insideZone |
| run (normal) | insideZone, zoneRead, wideZone, qbDraw, jetSweep |
| pass short | rpoSlant, rpoStick, rpoBubble, slant, spot, drag |
| pass medium | seam, smash, rpoPop |
| pass deep | post |
| signature pool (share 0.35) | dist ≤ 2 → rpoStick, rpoPop, zoneRead; else → rpoBubble, rpoSlant, rpoPop, zoneRead, bubbleScreen |

---

### `option` — make him wrong · passBias −0.12 · persona `.groundAndPound`|`.balanced`

**Signature (4):** `speedOption` · `zoneRead` · `endAround` · `toss`

**Install (16):** speedOption, zoneRead, insideZone, dive, toss, counter, endAround,
jetSweep, tushPush · bubbleScreen · flat, drag, fade · seam · goRoute · playActionDeep

| OC order | plays |
|---|---|
| run (dist ≤ 1) | tushPush, qbSneak, dive, insideZone |
| run (normal) | speedOption, zoneRead, insideZone, toss, counter, jetSweep, endAround |
| pass short | flat, drag, bubbleScreen, fade |
| pass medium | seam |
| pass deep | playActionDeep, goRoute |
| signature pool (share 0.38) | dist ≤ 2 → tushPush, dive, speedOption; dist < 8 → speedOption, zoneRead, toss, endAround; else → [] |

---

### Defensive scheme playbooks

`DCPersona.derive` (`CoordinatorPersona.swift:52`) is unchanged. "Weights" = the shell/blitz mix
the AI base logic should trend to, plus the scheme's `exoticPackage` pool
(`CoordinatorPersona.swift:158`) which today is hardcoded `[.doubleAGap, .zoneBlitz, .bearFront]`.

| scheme | signature (3-4) | install list | man% / blitz% / two-high% | exotic pool addition |
|---|---|---|---|---|
| `base34` | `base34` · `fireZone` · `creeper` · `edgeDog` | base34, fireZone, simPressure, creeper, edgeDog, doubleAGap, lbFire, safetyBlitz, cover1, cover1Robber, cover3Base, quarters, bearFront, nickelPackage, goalLineD, prevent | 30 / 42 / 25 | fireZone, creeper |
| `base43` | `cover2Shell` · `bearFront` · `lbFire` · `cloud2` | cover2Shell, cover3Base, cover6, quarters, cloud2, cover1, lbFire, doubleAGap, zoneBlitz, bearFront, nickelPackage, dimePackage, goalLineD, prevent | 18 / 28 / 45 | bearFront, doubleAGap |
| `cover3` | `pressBail`\* · `fireZone` · `cover1Robber` · `cover3Base` | cover3Base, cover1, cover1Robber, manFree, fireZone, lbFire, safetyBlitz, quarters, cover6, nickelPackage, bigNickel, goalLineD, prevent | 28 / 30 / 22 | fireZone |
| `pressMan` | `cover0` · `overload` · `manPress` · `cornerBlitz` | manPress, manFree, twoManUnder, twoManPress, cover1, cover1Robber, cover0, allOut, cornerBlitz, safetyBlitz, overload, edgeDog, dimeFire, nickelPackage, goalLineD, prevent | 72 / 48 / 20 | cover0, overload |
| `tampa2` | `tampa2` · `cloud2` · `cover6` · `simPressure` | tampa2, cover2Shell, cover6, cloud2, quarters, cover4Match, zoneBlitz, fireZone, simPressure, twoManUnder, nickelPackage, dimePackage, bigNickel, goalLineD, prevent | 15 / 22 / 62 | simPressure, zoneBlitz |
| `multiple` | `simPressure` · `creeper` · `cover6` · `bearFront` | tampa2, cover6, cloud2, cover2Shell, cover3Base, quarters, cover4Match, cover1, cover1Robber, manPress, manFree, fireZone, simPressure, creeper, doubleAGap, zoneBlitz, safetyBlitz, cornerBlitz, allOut, base34, bearFront, bigNickel, nickelPackage, dimePackage, goalLineD, prevent | 35 / 40 / 40 | simPressure, creeper, cover0 |
| `hybrid` | `cover1Robber` · `bigNickel` · `creeper` · `cover6` | cover1Robber, cover1, cover6, cloud2, quarters, cover4Match, manPress, manFree, twoManUnder, twoManPress, creeper, simPressure, fireZone, zoneBlitz, safetyBlitz, cornerBlitz, edgeDog, bigNickel, base34, nickelPackage, dimePackage, goalLineD, prevent | 45 / 35 / 38 | creeper, cover1Robber |

\* `pressBail` is **not** a new call — it is `cover3Base` called from `nickelPackage`. Listed as a
signature *label* only if the implementer wants a 15th named call; otherwise drop it and
`cover3`'s signature set is `fireZone · cover1Robber · cover3Base`.

---

## 3. Migration — every switch that must be extended

### 3.1 Compile-error switches (safe: the compiler finds them)

| site | file:line | what to add |
|---|---|---|
| `OffensivePlayCall.simulatorHint` | `PlayCall.swift:295` | one case per new play (table §1a) |
| `OffensivePlayCall.category` | `PlayCall.swift:58` | new tab strings |
| `OffensivePlayCall.blurb` | `PlayCall.swift:74` | blurbs from §1a |
| `OffensivePlayCall.schemes` | `PlayCall.swift:144` | inverted §2 lists |
| `RouteSpec.spec(for:)` | `RouteSpec.swift:93` | waypoints from §4 |
| `AdaptiveOpponentAI.tendency(of:)` | `AdaptiveOpponentAI.swift:90` | `tend` column from §1a |
| `DefensivePlayCall.coverage/pressure/runStopModifier` | `PlayCall.swift:434/458/477` | 7 dimension cases |
| `DefensivePlayCall.category` | `PlayCall.swift:419` | Coverage / Blitz / Front |
| `DefensiveCall.package` / `blurb` / `schemes` / `category` | `PlayCall.swift:653/678/703/640` | 14 named calls |

### 3.2 SILENT-DEFAULT switches (dangerous: no compile error, wrong behavior)

| site | file:line | default today | required edit |
|---|---|---|---|
| `OffensivePlayCall.formationFamily` | `PlayCall.swift:202` | `default: .baseGun` | explicit case for every new play; add `.pistol` and `.playAction` to the `FormationFamily` enum (L190) |
| `PlayChoreographer.offensePositions` | `PlayChoreographer.swift:251` | `default: break` → base gun | alignment branch for `.pistol` (QB 4.0 deep, RB beside at 4.2, slot −7, split 15) and for the new under-center runs (reuse the `.insideRun` branch: `power, duo, trap, tushPush, insideZone`), plus `.playAction` (QB 2.0, RB 6.0 downhill, split 15) and `wideZone, endAround` on the `.outsideRun` branch |
| `PlayChoreographer.stances` | `PlayChoreographer.swift:165` | `default: .shotgunQB` | add `power, duo, trap, tushPush, insideZone, paBoot, paCross, paGlance, playActionDeep` to the `.underCenter` list |
| `MatchupResolver.resolveRun` | `MatchupResolver.swift:454` | `inside = [...]` hardcoded list; unknown run ⇒ edge point-of-attack | add `insideZone, duo, power, trap, zoneRead, qbDraw, tushPush` to the inside list. `wideZone, endAround, speedOption` correctly stay edge |
| `OffensivePlayCall.goodAgainst` | `PlayCall.swift:228` | `default: false` | §3.4 table — includes cases for the three NEW coverage shells |
| `DefenseDiagramView` | `PlayDiagramView.swift:159–186` | `default:` draws man lines only if `manUnder`, i.e. a new shell renders as an EMPTY secondary | drawing branches for `tampa2`, `cover6`, `cover0` (§4) |
| `DefensivePlayCall.deep/shortCoverageModifier` | `PlayCall.swift:515/523` | `default: 0` | `tampa2`, `cover6`, `cover0` rows from §1b |
| `DefensivePlayCall.shellShortLabel` | `PlayCall.swift:502` | `default: rawValue` | `tampa2`→"Tampa 2", `cover6`→"Cover 6", `cover0`→"Zero" |

### 3.3 Man-coverage identity gates (`coverage == .manToMan`) — `cover0` must be added to all three

| site | file:line | edit |
|---|---|---|
| press/release/jam branch | `PlaySimulator.swift:891` | `[.manToMan, .cover0].contains(coverage) && passDistance == .short` |
| `coverageManWeight(package:)` | `PlaySimulator.swift:2550` | `cover0` = max man weight (≥ `manToMan`); `tampa2`/`cover6` = zone weights |
| `AdaptiveOpponentAI.DefenseSnap.init` | `AdaptiveOpponentAI.swift:143` | `isMan = [.manToMan, .cover0].contains(package.coverage)`; `isSingleHigh` unchanged (`cover0` has **no** deep help, so it must NOT count as single-high) |

Also: `DefensivePlayCall.audibleShells` (`PlayCall.swift:498`) — add `tampa2` and `cover6`
(zone rotations are legitimate line-of-scrimmage checks). Do **not** add `cover0` or `prevent`.

### 3.4 `goodAgainst` — pre-snap ✓ tags (cosmetic; sim never reads it)

| coverage | add |
|---|---|
| `.manToMan` | `shallowCross, angle, sluggo, backShoulder, endAround, speedOption, fade, yCross` |
| `.cover1` | `paCross, fourVerts, sluggo, dagger, yCross` |
| `.cover2` | `fourVerts, dagger, levels, smash, seam` (seam already) |
| `.cover3` | `smash, sail, snag, spot, backShoulder, comeback` |
| `.cover4` | `insideZone, duo, power, trap, zoneRead, rpoBubble, rpoStick, tushPush` |
| `.prevent` | `insideZone, duo, qbDraw, slipScreen, bubbleScreen` |
| `.tampa2` **(new case)** | `sail, smash, corner, fade, wideZone, endAround` — attack the sidelines |
| `.cover6` **(new case)** | `insideZone, power, mesh, shallowCross, snag` |
| `.cover0` **(new case)** | `bubbleScreen, tunnelScreen, slipScreen, rpoBubble, sluggo, fourVerts` |

### 3.5 AI pools — new plays are invisible to the AI until they are in these lists

| site | file:line | edit |
|---|---|---|
| `LiveGameEngine.recommendedRunCall` | `LiveGameEngine.swift:2286` | per-persona orders from §2 (the function already filters by `playerHasInstalled`) |
| `LiveGameEngine.recommendedPassCall` | `LiveGameEngine.swift:2302` | per-persona × depth orders from §2 |
| `OCPersona.signaturePool` | `CoordinatorPersona.swift:246` | signature pools from §2 |
| `AdaptiveOpponentAI.offensiveCounterCalls` | `AdaptiveOpponentAI.swift:274` | `.blitzHeavy` += `slipScreen, bubbleScreen, rpoSlant, qbDraw, angle`; `.manHeavy` += `shallowCross, yCross, angle, sluggo, endAround`; `.zoneHeavy` += `levels, snag, spot, dagger, smash`; `.singleHighHeavy` += `fourVerts, paCross, sluggo, backShoulder` |
| `AdaptiveOpponentAI.defensiveCounterCalls` | `AdaptiveOpponentAI.swift:249` | `.insideRun` += `base34`; `.outsideRun` += `cloud2, tampa2`; `.screen/.shortPass` += `twoManPress, edgeDog`; `.mediumPass` += `simPressure, cover1Robber`; `.deepPass` += `tampa2, cover6, bigNickel`; `.playAction` += `simPressure, cover6` |
| `DCPersona.exoticPackage` pool | `CoordinatorPersona.swift:158` | `[.doubleAGap, .zoneBlitz, .bearFront, .creeper, .simPressure, .cover0]` (keep the `distance >= 7` filter, and add `cover0` to it) |
| `CoachedGameView.categories` | `CoachedGameView.swift:1412` | `["Run","Screen","Short Pass","Medium Pass","Deep Pass","Play Action","RPO","Special"]` + short names at L1705 |

### 3.6 Archetype + quick-sim mapping (the two mappings the brief asks for)

**AdaptiveOpponentAI archetype** = `OffenseTendency`. It is what the AI defense keys on, what
`PlayMemory` accumulates, and what `counterConcepts` trades against. Full mapping:

| archetype | new plays mapped to it |
|---|---|
| `.insideRun` | insideZone, duo, power, trap, zoneRead, qbDraw, tushPush |
| `.outsideRun` | wideZone, endAround, speedOption |
| `.screen` | bubbleScreen, tunnelScreen, slipScreen |
| `.shortPass` | spot, snag, shallowCross, angle, fade, rpoBubble, rpoSlant, rpoStick, rpoPop |
| `.mediumPass` | levels, yCross, dagger, sail, smash |
| `.deepPass` | fourVerts, sluggo, backShoulder, hailMary |
| `.playAction` | paBoot, paCross, paGlance |

Balance consequence to watch: `.insideRun` gains 7 members and `.shortPass` gains 9. Because
tendency is recency-weighted over the *category*, a coach who calls `power → duo → trap` now
trips the inside-run key exactly as if he had called `insideRun` three times. That is correct and
intended, but it means the expansion does **not** let a coach hide from the AI by rotating
same-family plays — call that out in the release notes.

**Quick-sim abstraction** = the `PlayType` the call collapses to via `PlaySimulator.playType(for:)`
(`:263`), which is the *only* thing `GameSimulator` could ever see. Mapping:

| PlayType | new plays |
|---|---|
| `.run` | insideZone, wideZone, duo, power, trap, zoneRead, qbDraw, endAround, speedOption, tushPush |
| `.pass` | every screen, every short/medium/deep/PA/RPO case, hailMary |
| `.spike` / `.kneel` | none added |

Because `GameSimulator.simulate` passes `offensiveCall: nil` on every scrimmage snap, **no new
play ever reaches the quick sim** — season simulation, the balance harness and
`MultiSeasonSmokeTest` are byte-unaffected by §1a/§1b as pure additions. The two exceptions are
the hardcoded `.playActionDeep` (`GameSimulator.swift:682`) and `.slant` (`:771`) sites; leave both
alone. Coached games *do* change (the AI pools in §3.5 feed `LiveGameEngine`), so the on-device
coached-game feel needs an eyeball pass, not a harness re-gate.

### 3.7 Ship order (each step compiles and is independently testable)

1. `SimulatorHint` + enum cases + category/blurb/schemes/tendency (game builds; cards render blank art).
2. `RouteSpec.spec` waypoints (§4) → cards and 3D field come alive.
3. `formationFamily` + choreographer alignments + stances (§3.2) → audibles and pre-snap looks correct.
4. Defensive dimension cases + named calls + `DefenseDiagramView` + the three man gates (§3.3).
5. AI pools (§3.5) → the AI starts calling the new sheet.
6. `goodAgainst` (§3.4), `MatchupResolver` inside list, `audibleShells`.

---

## 4. Diagram spec — `RouteSpec` waypoints for every new play

Format is the existing one exactly: `W(depth, lateral)` in yards, LOS-relative.
`depth` = yards past the LOS (negative = backfield). `lateral` = cumulative offset from the
player's own alignment; **positive = toward his own sideline (outside), negative = inside/across**.
Roles: `0` QB · `1` RB · `7` WR-L · `8` WR-R · `9` slot · `10` TE. A role with no entry blocks.
`P` = `primaryRole`, `C` = `carrierRole`, `M` = `motionRole`.

### Runs

| play | routes | P / C / M |
|---|---|---|
| `insideZone` | `1: [W(-1.2,-0.8), W(1.5,-2.2), W(6,-1.6)]` | 1 / 1 / — |
| `wideZone` | `1: [W(-1.4,3.5), W(0,7), W(3.5,6.5), W(9,5.5)]` | 1 / 1 / — |
| `duo` | `1: [W(-1.0,-0.6), W(2.5,-0.8), W(8,-0.4)]` | 1 / 1 / — |
| `power` | `1: [W(-1.2,1.6), W(1.2,-1.8), W(5,-2.4), W(9,-2.0)]`, `10: [W(1.0,2.5)]` | 1 / 1 / — |
| `trap` | `1: [W(-0.8,0.4), W(2,-1.6), W(7,-2.2)]` | 1 / 1 / — |
| `zoneRead` | `1: [W(-1.0,2.5), W(1.0,4.5)]`, `0: [W(-0.8,-0.5), W(1.5,-3.5), W(6,-5.0)]`, `9: [W(2,1)]` | 1 / 1 / — |
| `qbDraw` | `0: [W(-4,0.5), W(-1,-1), W(4,-1.5), W(9,-1)]`, `7: [W(14,0)]`, `8: [W(14,0)]` | 0 / 0 / — |
| `endAround` | `7: [W(-1.5,-12), W(-0.5,-16), W(3,-18), W(9,-19)]`, `1: [W(-1.2,3.5), W(0,6)]` | 7 / 7 / 7 |
| `speedOption` | `0: [W(-0.5,2.5), W(1.5,5.5), W(4,7)]`, `1: [W(-1.5,5), W(1,9)]` | 0 / 0 / — |
| `tushPush` | `0: [W(1.0,0), W(2.0,0)]`, `1: [W(-0.4,0)]` | 0 / 0 / — |

`endAround` note: `carrierRole: 7` is a **non-RB carrier**. `carrierRole` is presentation-only
(`RouteSpec` lives in `UI/Match`; `PlaySimulator` picks its own rusher), so the visual will show
the WR carrying while the box score credits the RB — the same pre-existing mismatch `jetSweep`
already has (`carrierRole: 1` with `motionRole: 9`). If the choreographer chokes on a role-7
carrier, fall back to the `jetSweep` pattern: `carrierRole: 1`, `motionRole: 7`.
`speedOption`/`qbDraw`/`tushPush` use `carrierRole: 0` exactly like the shipped `qbSneak`.

### Screens

| play | routes | P |
|---|---|---|
| `bubbleScreen` | `9: [W(-0.5,3.5), W(0,6)]`, `7: [W(1,1)]`, `8: [W(12,0)]` | 9 |
| `tunnelScreen` | `8: [W(1,-2), W(1.5,-5)]`, `9: [W(0.5,2)]`, `7: [W(12,0)]` | 8 |
| `slipScreen` | `1: [W(-2.5,-1.5), W(-0.5,-4)]`, `7: [W(13,0)]`, `8: [W(13,0)]`, `9: [W(2,3)]` | 1 |

### Short passes

| play | routes | P |
|---|---|---|
| `spot` | `9: [W(5,-1), W(5.5,-3)]`, `10: [W(2,3.5), W(3,6.5)]`, `8: [W(6,0), W(9,5)]`, `7: [W(12,0)]` | 9 |
| `snag` | `7: [W(4,0), W(6,-4)]`, `9: [W(9,-1), W(13,4)]`, `1: [W(-1,4), W(0.5,7)]`, `8: [W(14,0)]` | 7 |
| `shallowCross` | `9: [W(1.5,-1), W(3,-16)]`, `8: [W(12,0), W(12,-9)]`, `7: [W(16,0)]`, `10: [W(6,-2)]` | 9 |
| `angle` | `1: [W(-1,3.5), W(1,6), W(3,1)]`, `10: [W(7,-2)]`, `7: [W(13,0)]`, `8: [W(11,0), W(10,-5)]` | 1 |
| `fade` | `8: [W(6,0.5), W(14,2.5)]`, `9: [W(4,-1)]`, `7: [W(10,0), W(9,-1)]`, `10: [W(3,2)]` | 8 |

### Medium passes

| play | routes | P |
|---|---|---|
| `levels` | `8: [W(6,0), W(7,-10)]`, `7: [W(12,0), W(13,-11)]`, `9: [W(3,3)]`, `1: [W(-1,4)]` | 7 |
| `yCross` | `10: [W(4,-2), W(10,-14), W(16,-24)]`, `8: [W(20,0)]`, `9: [W(12,-1)]`, `7: [W(6,0), W(5,-1)]`, `1: [W(-1.5,4.5), W(0,7.5)]` | 10 |
| `dagger` | `9: [W(16,-1)]`, `8: [W(14,0), W(14,-14)]`, `7: [W(20,0)]`, `1: [W(-1,4)]` | 8 |
| `sail` | `10: [W(3,3), W(4,7)]`, `8: [W(12,0), W(16,6)]`, `9: [W(18,-1)]`, `7: [W(14,0), W(12,-1)]` | 8 |
| `smash` | `8: [W(5,0), W(4,1.5)]`, `9: [W(8,-1), W(16,6)]`, `7: [W(14,0), W(12,2)]`, `10: [W(5,-2)]` | 9 |

`yCross` uses `formationFamily .crossSet`, so the choreographer flips the slot right
(`PlayChoreographer.swift:262`) and the TE crosser and the slot dig genuinely X the field —
same trick `.cross` already uses.

### Deep passes

| play | routes | P |
|---|---|---|
| `fourVerts` | `7: [W(24,0)]`, `8: [W(24,0)]`, `9: [W(22,-2)]`, `10: [W(20,-3)]`, `1: [W(-1,4)]` | 9 |
| `sluggo` | `8: [W(3,-2.5), W(6,-3.5), W(22,-3)]`, `7: [W(16,0)]`, `9: [W(5,-1)]`, `10: [W(6,-2)]` | 8 |
| `backShoulder` | `8: [W(18,0), W(16,1.5)]`, `7: [W(20,0)]`, `9: [W(6,-1)]`, `10: [W(5,2)]` | 8 |
| `hailMary` | `7: [W(42,1)]`, `8: [W(42,-1)]`, `9: [W(40,-2)]`, `10: [W(38,2)]` | 8 |

`hailMary` depths clamp in `PlayDiagramData.norm` (min y 0.04) — that is fine, the card reads as
four lines running off the top, which is exactly right.

### Play action

| play | routes | P |
|---|---|---|
| `paBoot` | `0: [W(-3,-1), W(-1.5,6), W(-1,9)]`, `10: [W(2,4), W(3,8)]`, `8: [W(12,0), W(15,7)]`, `9: [W(4,-1), W(6,-14)]`, `7: [W(18,0)]` | 8 |
| `paCross` | `7: [W(8,0), W(14,-13), W(19,-26)]`, `9: [W(3,-1), W(6,-12)]`, `8: [W(22,0)]`, `10: [W(6,3)]` | 7 |
| `paGlance` | `8: [W(3,0), W(9,-6)]`, `7: [W(3,0), W(9,-6)]`, `9: [W(5,-1)]`, `10: [W(4,2)]` | 8 |

`paBoot` gives role 0 a route — the QB rollout track. That is legal (`.qbSneak`, `.spike`,
`.kneel` already route role 0) and it is what makes the boot read as a boot on the card.

### RPO

Every RPO draws the give track for role 1 so the card shows the mesh point. Keep the RB track
short (it is a fake on the pass resolution).

| play | routes | P |
|---|---|---|
| `rpoBubble` | `9: [W(-0.5,3.5), W(0,6)]`, `1: [W(-1,-1), W(2,-2)]`, `7: [W(1,1)]`, `8: [W(11,0)]` | 9 |
| `rpoSlant` | `8: [W(2.5,0), W(8,-6)]`, `1: [W(-1,-1), W(2,-2)]`, `9: [W(1,2)]`, `7: [W(11,0)]` | 8 |
| `rpoStick` | `10: [W(5.5,0), W(5,2.5)]`, `9: [W(2,3.5)]`, `1: [W(-1,-1), W(2,-2)]`, `8: [W(12,0)]` | 10 |
| `rpoPop` | `9: [W(3,-1), W(10,-2)]`, `1: [W(-1,-1), W(2,-2)]`, `8: [W(12,0)]`, `7: [W(12,0)]` | 9 |

### Defensive diagrams

`DefenseDiagramView` (`PlayDiagramView.swift:99`) draws from `(coverage, blitz)`. Three new
shells to add to the switch at L159–186:

| shell | drawing |
|---|---|
| `tampa2` | Cover 2 base (two deep halves, corners squat) **plus** the Mike dropping straight up the middle to ~18 yd — the pipe is the whole visual identity |
| `cover6` | quarters bracket on the field side (two deep quarters), Cover 2 half on the boundary side (one deep half + squatting corner) |
| `cover0` | five press man arrows straight downfield, **no** deep-safety marker at all — the empty deep third is the read |

---

## 5. Summary counts

| | existing | new | total |
|---|---|---|---|
| `OffensivePlayCall` | 31 | **34** | 65 |
| offensive tabs | 5 | 3 | 8 |
| `DefensivePlayCall` dimensions | 17 | **7** | 24 |
| `DefensiveCall` named calls | 19 | **14** | 33 |
| defensive tabs | 4 | 0 | 4 |
| `FormationFamily` | 8 | 2 (`.pistol`, `.playAction`) | 10 |

New offensive cases by tab: Run 9 · Screen 3 · Short 5 · Medium 5 · Deep 3 · PA 3 · RPO 4 · Special 2.
