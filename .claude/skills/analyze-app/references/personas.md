# Persona Checklists

The same evidence (screenshots, video, functional-sweep table) is read through
four lenses. Each persona produces its own findings list; findings can
conflict (casual wants less data, hardcore wants more) — report the conflict,
propose the resolution (progressive disclosure, defaults + drill-down).

## 1. Designer

Judge with measurements, not vibes.

- Hierarchy: what do the eyes hit 1st/2nd/3rd? Is that the right order for the
  screen's job?
- Typography: sizes form a scale? Monospaced numbers in tables? Nothing below
  ~12 pt at iPad viewing distance (~60-70 cm)?
- Spacing: consistent padding rhythm? Grid alignment? Crowding or dead zones?
- Color: design-token discipline (Theme.swift), semantic colors used
  semantically, gold reserved for emphasis? Contrast measured >= 4.5:1 for body
  text (compute from screenshot pixels — do not eyeball).
- Components: consistent corner radius, card style, chip vs button distinction,
  44 pt touch targets.
- Motion (animated screens): does the motion profile show life (baseline >= 1)
  without chaos? Do transitions ease, or teleport?

## 2. Casual player

Someone who likes football but reads no manuals. First-session experience.

- 10-second rule: can they say what this screen is for and what to do next
  within 10 s? Is there ONE obvious primary action?
- Jargon: OVR, cap hit, 3-technique, Cover 2 — is each term either avoidable,
  explained inline, or safe to ignore?
- Safe defaults: can they make an okay decision without understanding
  everything (presets, recommendations, auto options)?
- Overwhelm: is advanced data hidden behind drill-downs rather than front and
  center? Would they feel stupid here?
- Feedback: after acting, do they SEE what happened and whether it was good
  (color, banner, sound, delta)?

## 3. Hardcore player (tosipelaaja)

A franchise-mode veteran who plays 20 seasons and min-maxes.

- Decision data complete: every number needed for THIS screen's decision
  visible or one tap away? (Roster: OVR/age/contract/injury/trend. Draft:
  grade+confidence, need, comparables. Trade: value meter, cap effect. etc.)
- Comparability: can two options be compared side by side without memorizing?
- Trends & history: is there a trajectory (arrows, sparklines, past seasons),
  or only a snapshot?
- Efficiency: batch actions, sorting, filtering, shortcuts — does a 100th visit
  feel fast?
- Trust: are derived numbers explained (why is this grade a B+)? Hidden dice
  rolls that feel arbitrary breed distrust.

## 4. Game developer

Systems thinking: is this screen pulling its weight in the game loop?

- Essential systems: does the screen surface everything the design says it
  should (check TODO.md/BACKLOG round logs for what was built)? Anything
  implemented in engine but invisible in UI?
- Meaningful choice: does the screen present real trade-offs, or a dominant
  strategy / fake choice?
- Feedback loop: does the player's last decision visibly pay off here (morale
  after presser, dev report after focus training)?
- Reference bar: name what best-in-class looks like for this screen (Madden
  franchise hub, FM squad screen, OOTP manager view) and list the 2-3 gaps
  that matter — not cosmetic ones.
- Fun test: if this screen disappeared and became a menu item + auto-resolve,
  would the game be worse? If not, the screen needs a reason to exist.

## Report format per screen

```
## [Screen] — persona findings
### Designer        (measured: contrast X:1, QB height Y%, ...)
1. [High] ...
### Casual player
1. [Blocking] First-time user cannot tell what Advance does ...
### Hardcore player
1. [Missing] No trend arrows on OVR ...
### Game developer
1. [Gap] Engine tracks X but screen never shows it ...
### Conflicts & resolution
- Casual wants fewer numbers vs hardcore wants more -> default collapsed, expander
### Functional sweep: N controls, N PASS, N DEAD, N STUB, N BUG (table below)
```
