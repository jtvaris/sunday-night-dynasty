# Presentation Polish Plan — Broadcast-Quality Coach Mode

**Author:** synthesis agent · **Date:** 2026-07-25 · **Branch:** `feat/skeletal-mocap-players`
**Status:** roadmap only — no repo code touched. A balance workflow is concurrently editing Engine
files; **do not build until that lands and the tree is clean.** The installed sim binary is **stale**
(dated Jul 24 11:27, before the Mental Readiness feature at 16:55) — any on-device verification of new
UI requires a fresh reinstall.

> Synthesizes three design tracks (3D scene look, coach-mode UI, animation naturalness), the
> fresh-eyes capture QA, and the visual-implementation code audit into **one** ordered roadmap.
> Conflicts between tracks are resolved in §0. Every item names its owner skill/tool, the exact
> files/assets, and how it is verified.

---

## Vision

Coach mode already reads as a competent **PS2 / Madden-2000-era** football broadcast: a legible night
field, 22 independently-skinned mocap players holding per-position stances, a real gold-on-navy UI
design system, and a genuinely broadcast-grade color grade (HDR + bloom + SSAO + vignette on
`SCNCamera`). The gap to the bar the user set — **Madden 2005 mocap quality, a living stadium, a
broadcast presentation** — is not the grade and not the engine. It is four concrete things: (1) the
players wear generic 6-atlas uniforms that bake the same "PLAYER / 10" onto everyone; (2) the world is
dead — flat-fog sky, speckle crowd, a legless procedural referee, empty sidelines, one shadow-caster;
(3) the animation vocabulary is thin — **one** run clip stride-scaled for every speed, no getups after
piles, repeated tackles; (4) the presentation under-sells its own systems — the HUDMirror deliberately
withholds the result until the play finishes, then reveals it with a plain capsule slide instead of a
broadcast stinger. This plan closes those four in three waves: **Quick Wins** (the merges, rig, sky,
HUD hierarchy, camera beat sheet, kicker — 1-2 sessions of high-leverage, low-risk work), **Medium**
(card art, contact-variety clips, world life, number decals, weather), and one **Flagship** (the
locomotion blend set — the run at the quality bar). The identity guardrail throughout: **midnight-navy
+ stadium-gold** stays; every UI change is hierarchy, state, contrast, or motion — no re-skin.

---

## §0 — Conflict resolutions (read before executing)

The three tracks overlap; where they differ, this is the ruling:

1. **Tint merge = HUNK CHERRY-PICK, never a file copy.** Track A read the worktree diff directly:
   the branch lacks HEAD's `stanceQBGun/stanceRB/stanceLB/stanceCB` variant pools and
   `throwHandWorldPosition()`. TODO.md:99 claims the branch was reset to the feature tip (9e9f4f2), so
   the two disagree — **resolve by diffing the worktree file against current HEAD at merge time and
   porting only the tint regions**, regardless of the branch pointer. Never `cp` the whole file.
   (Details in QW-1.)

2. **Apex "black sky" fix and the sky/atmosphere upgrade are the SAME fix — do it once.** Track A's
   gradient `background.contents` and Track C's "apex framing black sky" residual (TODO.md:71) are one
   change in `applyFog` (`FootballFieldScene.swift:5545`). Owner: `scenekit-shader-vfx`. (QW-3.)

3. **Mesh-hold 0.5s→0.75s is not a standalone knob — it is one row of the camera beat sheet.** Track C
   folds `meshHoldSeconds` (`FootballFieldScene.swift:388`) into a per-play-type beat table; the 0.75s
   contact hold and the catch-hold (which fixes catch-moment continuity) are cells in it. (QW-6.)

4. **Result-stinger is delivered in two cuts, not one.** Track B honestly sized the full broadcast
   stinger as **L**. Resolution: **QW-5 ships "reveal v1"** — a color-coded plate keyed to outcome
   severity, timed to land on the whistle, reusing the existing `bannerOverlay` machinery — inside the
   quick-win window; **MED-6 ships "stinger v2"** — the two-stage gold-rule wipe + `numericText` score
   tick + `cameraBump` sequencing as a real choreography subsystem. This honors both the prompt's
   grouping and Track B's sizing.

5. **Number decals: the free luminance-demote ships with the tint (QW); the per-player bone-parented
   decal is Medium.** Track A/baseline agree: the tint modifier can multiply the baked "10" toward the
   fabric mean for free (QW-1 add-on); the real fix — a bone-parented `SCNPlane` decal on the
   **skeletal** path — is MED-4.

6. **Locomotion stays on SceneKit (Option A discrete tiers). RealityKit is NOT triggered.** The
   baseline doc named RealityKit as the sanctioned fallback; Track C de-risked it away. Ruling in the
   Flagship section with the full risk call.

7. **Post-FX heavier than the current `SCNCamera` grade is REPLAY-ONLY.** DoF / full-screen blur must
   never run on the live 22-player camera. Non-negotiable TBDR guardrail. (MED-7 / deferred.)

8. **Meshy is API-key gated and the key is ABSENT** (`MESHY_API_KEY` unset as of this writing). Every
   Meshy item (ref replacement, hero props, retexture uniforms) must run the skill's Step-0 detection
   first and **fall back to Blender-MCP PolyHaven/Sketchfab free assets or defer**. Crowd shimmer and
   the tint (no key needed) are unaffected. (MED-3.)

**Housekeeping, do first:** restore the test sim play-clock (`playClockSetting` is currently `off`) to
`-string 10` before handing the sim back for real play — but leave it `off` while running tap-driven
QA. And note: `render_verify.py`, the 34 `PlayerClip_*.usdc`, and `PlayerClip_sprint.usdc` are all
confirmed present in the tree.

---

## §1 — QUICK WINS (1-2 sessions)

Highest leverage per hour, low risk, mostly self-contained. Ordered by dependency. Effort key:
**S** = hours · **M** = a few days · **L** = week+.

### QW-1 · Team-color tint merge (+ free number demote) · **S** · owner: `scenekit-shader-vfx`
The single worst finding in the capture ("every jersey reads PLAYER / duplicate 10"). A ready
`.surface` shader modifier — `applyTeamColors(jersey:pants:)` recoloring the 8-tile Ochi UV atlas by
UV band, luminance-preserving, **zero extra texture reads/passes** (TBDR-sanctioned) — sits in the
worktree.
- **Merge technique:** cherry-pick the hunks (see §0.1). Port into
  `dynasty/dynasty/UI/Match/SkeletalFigure.swift`: the `applyUniform`→`applyTeamColors` call site
  (~:248), the `teamTintSurfaceModifier` builder + `jerseyTiles/pantsTiles/baseUniformIndex` constants,
  the `rgbVector(_:)` helper; delete the dead `uniformColors`/`nearestUniformIndex`. Keep HEAD's
  `throw_a/throw_c` timings and stance pools. `Uniform.pants` is already threaded into
  `SkeletalFigure.init` (`FootballFieldScene.swift:5214`) — change is entirely internal to
  `SkeletalFigure.swift`.
- **Source:** `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/.claude/worktrees/agent-a6152ef59de58bb7a/dynasty/dynasty/UI/Match/SkeletalFigure.swift`
- **Free add-on:** in the same modifier, multiply the tile-4 chest/back luminance toward the fabric
  mean so the baked "10" fades to a low-contrast ghost (the real per-player number arrives in MED-4).
- **Why first:** unblocks nothing technically, but it fixes the dominant visual defect and — critical
  per Track C — **must land before any SkeletalFigure locomotion/getup edits** (same file) to avoid a
  merge conflict with the Flagship.
- **Verify:** `dynasty-sim-qa` formation-camera screenshot → home red / away white-navy, skin
  untouched, no "10" bleed. (Atlas caveat: tile 5 fuses helmet+thigh+socks, so a pure helmet exclude
  is impossible on this asset — accepted.)

### QW-2 · Lighting rig: rim light + soft contact shadow + drop blob · **S-M** · owner: `scenekit-shader-vfx`
Today `buildLighting()` (`FootballFieldScene.swift:5450`) has exactly one shadow-caster; players read
as flat silhouettes against the dark bowl, and each carries a hard cylinder blob-shadow decal
(`makePlayerNode:5193`, a=0.38) — the PSX-era tell the capture flagged.
- **2a. Rim/back light (S):** add a 3rd `.directional` light opposite the key, warm sodium
  (`1.0,0.95,0.85`), ~350 intensity, `castsShadow=false`, skimming shoulders/helmets from
  behind-camera. No new shadow pass → ~free on TBDR.
- **2b. Soften the one caster (S):** raise `shadowRadius` 3→5 and `shadowSampleCount` 16→24 (:5456-61);
  then **drop the per-player blob cylinder** in favor of the now-soft real cast shadow (keep blob only
  as the `useSkeletalFigures==false` fallback). Removing 22 cylinders is a net draw-call win.
- **Do NOT** add a second shadow-casting light (each caster = a full extra shadow-map pass — the real
  cost with 22 skinned players).
- **Verify:** `visual-design-loop` — screenshot pre-snap; players lift off the crowd; contact shadow
  is a soft penumbra, not an ellipse decal. Confirm FPS on a **real iPad**, not the sim.

### QW-3 · Apex / sky gradient fix · **S** · owner: `scenekit-shader-vfx`
Resolves both the capture's dead backdrop and TODO.md:71's "apex framing black sky." `applyFog`
(`FootballFieldScene.swift:5545`) sets `background.contents` to a flat navy fill.
- **Technique:** replace with a vertical-gradient dusk/night image (a `UIGraphicsImageRenderer` 2×512
  gradient: deep-navy zenith → warm sodium horizon matching the floodlight `1.0,0.98,0.9`). Keep the
  fog color equal to the gradient's horizon band so the far field still dissolves seamlessly. Zero
  geometry, zero runtime cost. (HDRI + `lightingEnvironment` IBL is the later MED upgrade, folded into
  MED-3.)
- **Verify:** `dynasty-sim-qa` capture of a kickoff/deep-pass apex frame → no black wedge; the bowl top
  meets a graded sky.

### QW-4 · Kicker approach + strike clip · **S** · owner: `blender-game-asset-pipeline`
Kicker reads as "no step → plant → strike"; `kick_a/kick_b` windows start at `lo≈0.25`, already past
the approach (TODO.md:69 residual, K3). No new mocap needed.
- **Technique:** re-slice the existing pack kick segments with a wider window (`kickshort/kickmed/
  kickgoal.kick` at `lo≈0.10`) to include the approach steps; re-export `PlayerClip_kick_a/b.usdc`;
  tune `actionHitFraction["kick_*"]` so foot-through-ball still lands on the ball-launch beat. Note
  `PlayerClip_kick.usdc` already authored per task #14 — reconcile with that.
- **Files:** `tools/asset-pipeline/pack_segments.json`, `rokoko_retarget.py`, then
  `dynasty/dynasty/Resources/`.
- **Verify:** `render_verify.py` grounded PASS; on-device FG/kickoff shows a readable 2-3 step approach,
  ball leaves on the strike frame.

### QW-5 · HUD hierarchy + kickoff chip-leak gate + result-reveal v1 · **M** · owner: `ui-ux-pro-max` + `design-for-ai`
Three interlocking UI wins. **Prereq: the token foundation (QW-5a) must land first.**
- **5a. Token foundation (M, keystone):** in `dynasty/dynasty/UI/Common/Theme.swift` add two layers on
  the existing primitives — **semantic aliases** (`statusOffense/statusDefense/chipKey/chipInfo/
  ctaPrimary/diagramInk/diagramMotion/diagramBlitz`), a **`DSType`** skip-step scale (overline 9 →
  score 34 mono, replacing ~40 raw `.system(size:)` calls), and **`DSElevation`** (navy-tinted, never
  pure-black shadows — fixes the "flat charcoal pills" note). Add two remedial primitives from the
  contrast audit: **`textTertiaryReadable #7C8BA1`** (~4.6:1 on card, replaces the failing
  `textTertiary #64748B` at 3.51:1) and **`dangerText #F87171`** (~6:1, for status-red *text*; keep
  `#EF4444` for fills). Every other UI item consumes these — land it first to avoid double-editing call
  sites.
- **5b. HUD hierarchy (M):** in `dynasty/dynasty/UI/Match/CoachedGameView.swift`, make the **clock the
  single dominant anchor** in `scoreboardBar` (:502); collapse the 3 stacked meta chips (PLAYOFFS/
  DIVISION/weather) into one priority badge; split `situationStrip` (:648) into two tiers — status
  chips quieter (down&distance in `chipKey`, field-pos/possession as neutral chips with a **colored
  leading dot**, not failing red text — "no info by color alone"), action buttons stay the heavy 44pt
  tier.
- **5c. Kickoff chip-leak gate (the design constraint):** the situation chips + possession pill bind to
  the `shown` HUDMirror and render "1st & 10 · OWN 22 · BUF ball" at f009 **before the kick**. Gate
  them on a `situationRevealed` flag driven by the existing reveal machinery (mirror
  `revealHUD(situation:)` at :3415) — hide them while `engine.pendingKickoff != nil`. Reads as a
  broadcast special-teams down, not a bug.
- **5d. Result-reveal v1:** color-code the existing result banner (`bannerOverlay:2370`) by outcome —
  gold for offense score, `dangerText` for a takeaway against you, `statusOffense` green for a takeaway
  you got — timed to land on the whistle the mirror already waits for (`revealHUD`, :3632). The full
  two-stage stinger is MED-6.
- **Verify:** `accesslint` MCP re-checks every new text/bg pair ≥4.5:1; `visual-design-loop`
  screenshot pass on scoreboard + a kickoff (chips absent pre-kick) + a TD (reveal color correct).
  **Requires a fresh build** (stale-binary caveat).

### QW-6 · Camera beat sheet + hitstop/slow-mo + mesh-hold extension · **M** · owner: FootballFieldScene (scene timing)
Camera today is all eased glides + a 0.5yd whisper dolly, one global `meshHoldSeconds = 0.5`
(`FootballFieldScene.swift:388`), no cuts, no slow-mo. Promote the constant into a **per-play-type beat
table** read by the `followHoldUntil` mechanism (:3398):

| Play type | Pre-snap | Snap | Follow | Contact beat | Result |
|---|---|---|---|---|---|
| Inside/Outside run | coach hold | whisper-in | follow carrier | **hold 0.75s on pile** | glide to spot |
| Short/Deep pass | coach hold | hold LOS | follow ball | **hold on catch** (fixes continuity) | glide/replay |
| Sack | coach hold | tighten pocket | — | **hitstop 0.2s** + `cameraBump` | glide |
| Kickoff | high wide | — | **ball-cam through the catch** | hold on reception | follow return |
| FG | behind posts (`kickCamera`) | — | — | strike hold | ball flight |
| TD | — | — | follow | **slow-mo ramp** into endzone | celebrate/replay |

- **6a. Beat sheet (M):** pure timing in `FootballFieldScene`/`CoachedGameView`, no clip authoring.
  Bumps the contact hold to the flagged 0.75s and adds a catch-hold that resolves the catch-moment
  continuity gap (TODO.md:71) once MED-8's returner catch is wired.
- **6b. Hitstop + slow-mo ramp (S):** 0.15-0.25s near-freeze + light `cameraBump` (:2774) on big
  tackles; scale `currentPlaybackRate` down over TD/turnover replays. The two clearest weight/impact
  cues the Madden bar has and this scene lacks.
- **Verify:** `dynasty-sim-qa` scripted capture (1 frame/0.5s) of one play per row → each beat lands,
  pre-snap not spoiled, contact held, no black-sky apex; `analyze-app` motion judge on the TD ramp.

**Quick-wins Definition of Done:** tint renders 32-team colors with no "10" bleed; players lift off the
background under a soft cast shadow; no black-sky apex; kicker has a readable approach; scoreboard has
one dominant anchor and all HUD text passes AA; kickoff chips gated; result banner color-timed to the
whistle; every play type has a distinct camera beat with a 0.75s contact hold. **Verified via:**
`visual-design-loop` (UI), `dynasty-sim-qa` frame-QA (scene/camera), `render_verify.py` (kicker clip),
`accesslint` (contrast), on-device eyeball on a **fresh build**.

---

## §2 — MEDIUM (asset & presentation quality)

Depends on Quick Wins landing (tokens, lighting, tint). Each is a few days.

### MED-1 · Field material: mipmaps/aniso + normal + wear + crisp lines · **M** · owner: `scenekit-shader-vfx`
Turf is a procedural 128² speckle (`turfTexture:3998`) tiled on an `SCNBox`, no normal map, no mipmaps
— the capture's "muddy lines/numbers at distance" is minification aliasing.
- **1a (S, first):** set `mipFilter=.linear` + `maxAnisotropy=8` on the turf and yard-number materials
  (`buildNumbers:4255`) → crisp lines immediately.
- **1b (M):** author a tiling grass normal map (PolyHaven via Blender-MCP, stored linear/non-sRGB) +
  a channel-packed detail/wear mask (R=mow-stripe, G=high-traffic wear, B=AO) sampled once in a
  `.surface` modifier to darken the LOS and hashes. Field is a single low-overdraw plane → cheap.
- **1c (S opt):** fold LOS/first-down markers (`buildMarkers:4598`) into the bloom threshold for a
  wet-paint-under-lights glow.
- **Verify:** `visual-design-loop` pulled-back screenshot → crisp lines, turf relief + wear.

### MED-2 · Player material: ball-carrier rim + selection highlight · **M** · owner: `scenekit-shader-vfx`
The clearest "who has the ball / who am I controlling" cue, and it reads as broadcast player-tracking.
Skill §2 fresnel recipe: `.surface` modifier `emission.rgb += rimColor * pow(1 - saturate(dot(N,V)), p)`,
**half precision, gated to ≤2 materials** (current carrier + pre-snap selected man), applied on select
/ cleared on deselect. Warm gold (`1.0,0.85,0.2`, p=3.0) for the carrier; cool blue for the selected
pre-snap player. Optional jersey-sheen (`metalness`/`roughness` nudge) so helmets catch the new rim.
**No toon/outline** — it fights the photoreal grade. Files: `SkeletalFigure.swift`.
- **Verify:** on-device — the ball glows to its carrier through a handoff; selection reads pre-snap.

### MED-3 · World life: crowd shimmer + referee + sideline props · **M-L** · owner: `scenekit-shader-vfx` + Meshy/Blender-MCP
- **3a. Crowd shimmer (S, no key):** a `.fragment`/`.surface` modifier on the 3 crowd tiers
  (`buildStadium:4449`, `crowdTexture:4556`) animating `emission` with `u_time` (hash the UV,
  `sin(u_time+hash)`) so the phone-screen speckle twinkles instead of sitting dead. Far, low-res,
  `castsShadow=false` → nearly free. Also delete the dead unreferenced `crowdTexture()` at :4087.
- **3b. Referee + sideline props (M, API-key gated):** replace the legless `buildReferee()` (:4621)
  and populate the empty sideline (benches, cooler+table, chain-crew down marker, first-down chains,
  broadcast camera, goalpost pad, headset coach). **Run Meshy Step-0 detection first — key is
  currently absent.** If no key: fall back to Blender-MCP PolyHaven/Sketchfab free assets, or defer.
  Route every asset through `blender-game-asset-pipeline` conventions (height-normalize `TARGET_H=1.9`
  for figures, Z-up/+Y-face/feet-at-0, material slots `JERSEY/PANTS/HELMET/SKIN`, export `.usdz`).
  Instance benches/coolers; keep far props shadow-off. ~150-200 credits for 8 core assets if Meshy —
  present the cost summary and get user confirmation before spending.
- **3c. HDRI sky/IBL (M, upgrade of QW-3):** a PolyHaven dusk HDRI as both `background.contents` and
  `scene.lightingEnvironment.contents` (intensity ~0.3-0.5) for free image-based ambient on helmets/
  pads. Dim-exposure so it doesn't fight the night grade.
- **Verify:** broadcast-camera `dynasty-sim-qa` screenshot → living, populated sideline; no legless ref;
  stands shimmer. FPS held on a **real iPad**.

### MED-4 · Per-player number decal (skeletal path) · **M** · owner: `scenekit-shader-vfx` + `blender-game-asset-pipeline`
Finishes what QW-1's luminance-demote started. The mesh has `addNumberDecals` (`:3960`) but gated to
the kit/procedural path (`figure.childNode(withName:"body")` at :5232) which the skinned rig doesn't
expose. Attach the existing `numberTexture(number, darkText:)` `SCNPlane` front/back decals to the
**skeletal** content root, parented to the upper-spine bone so they ride the deform; reuse
`isLightColor(jersey)` for contrast; wipe the baked number region in the tint modifier. 2 unlit,
`castsShadow=false` quads/player (cheap). Files: `SkeletalFigure.swift`, `FootballFieldScene.swift`.
- **Verify:** formation screenshot → correct unique per-player numbers on-mesh, replacing the dim
  floating billboard as the primary read.

### MED-5 · Contact variety: getups + 3 new tackle clips + block-shed + interpenetration · **M** · owner: `blender-game-asset-pipeline`
The thinnest part of the animation vocabulary. Mine the **unused `pack_segments.json` segments**
(retarget + trim + gate, not from-scratch authoring).
- **5a. Getups (M, biggest gap):** downed **skeletal** men never rise — `fall()`
  (`FootballFieldScene.swift:2800`) ignores `getUpDelay/stayDown` on the skinned branch. Retarget
  `catchroll.getup / runcatch1.getup / holder3.getup` → `PlayerClip_getup_a/b/c.usdc`; add a `"getup"`
  variant pool + a `rise()` on `SkeletalFigure`; wire the ignored `getUpDelay` so a pile unstacks
  raggedly.
- **5b. 3 new tackle clips (M):** `tackled.hit`, `catchroll.roll`, `runcatch1.down` →
  `tackle_c/tackle_roll/fall_fwd_b`, added to the variant pools so consecutive hits differ.
- **5c. Block-shed (S-M):** Mixamo "shove/push-off" retarget — the timing already exists (shed-then-
  burst sack, `PlayChoreographer.swift:2454`); this adds the pose.
- **5d. QB/rusher interpenetration (S, choreography):** clamp the rusher's burst endpoint to a
  minimum-separation radius from the QB with a lateral rip-past offset (TODO.md:71). Mirror-safe.
- **5e. Tackle entry alignment (S-M, choreography):** stop the tackler's approach at a contact radius
  (~1.0yd) and fire the tackle only when within radius AND facing, so the lay-out drives *into* the
  carrier (`faceTowardCarrier:2790`, `tackleSteps:1627`).
- **Verify:** `render_verify.py --fall` monotonic-descent PASS on each grounded clip (the exact gate
  that caught the mis-seated fall); on-device 20-play run → no two identical hits, every pile clears
  before the next snap, no mesh overlap on a flush.

### MED-6 · Result stinger v2 (broadcast lower-third) · **M** · owner: `ui-ux-pro-max` + FootballFieldScene hooks
Upgrades QW-5d into the payoff of the whole HUDMirror gating system. Add **`DSMatchMotion`** tokens to
`Theme.swift` (generalize `DraftAnimation`: `microIn 0.18`, `bannerIn 0.32/bannerOut 0.22` — exit ≈70%
of enter, `stingerReveal 0.5`, spring physics, a `reduceMotion` branch on every one, extending the
clock-pulse discipline at :572). When `revealHUD()` fires after a play settles:
- **Big play (TD/turnover/sack):** two-stage — a thin gold rule wipes L→R (0.25s), then the headline
  sets with the existing `contentTransition(.numericText())` score-tick (:598) firing in the same beat
  + one `cameraBump`. Reveal order: field settles → stinger wipes → score ticks → feed line promotes.
- **Routine play:** the calm capsule, on `DSMatchMotion.bannerIn`.
- Interruptible — a tap dismisses it; never blocks the next call. Panel transitions (kickoff/4th-down/
  XP) slide from their trigger region.
- **Verify:** `analyze-app` motion judge on a captured TD sequence → the delay reads as a build, not a
  lag; Reduce-Motion path is a clean fade. **Requires a fresh build.**

### MED-7 · Weather surface response · **S-M** · owner: `scenekit-shader-vfx`
`setWeather` (`:5504`) already tunes rain/snow slabs. Two cheap upgrades: **7a (S)** in rain, raise the
turf `metalness`/lower `roughness` for a specular sheen that catches the floodlight bloom (wet look) +
faint line reflectivity — pure material-value swap; **7b (M opt)** per-player breath vapor
`SCNParticleSystem` in cold/snow games, gated to the broadcast camera only (coach camera too close),
22 low-birthrate emitters — measure. `wind`/`dome` render nothing today — leave as-is.
- **Verify:** on-device rain game → field visibly wets; snow game → breath reads without FPS loss on a
  real iPad.

### MED-8 · GamePlanView Mental Readiness polish + returner catch · **S** · owner: `ui-ux-pro-max` / `blender-game-asset-pipeline`
- **8a. Mental Readiness (S, UI):** in `dynasty/dynasty/UI/Roster/GamePlanView.swift` (mentalRow
  :663-763): swap the failing `textTertiary` position label + `coordinatorRow` blurb (:639) to
  `textTertiaryReadable`; add a tick at the 45/75 morale thresholds + keep the numeric value ("no info
  by color alone"), thicken the bar to 6pt with an inset track; give the card `DSElevation.card` so it
  fills the 340px column void the capture flagged. **Only photographable after a build newer than
  Jul 24 16:55.**
- **8b. Returner catch (S, clip/choreography):** fire `catchpunt.catch`/`runcatch.catch` at reception
  with `landAfter` synced to ball arrival, then transition to the loco return — closes the catch-moment
  continuity gap jointly with QW-6's catch-hold and the kickoff-arc.
- **Verify:** `accesslint` on the label/blurb; `dynasty-sim-qa` reception capture → catch on-screen,
  ball continuity holds.

**Medium Definition of Done:** turf has relief + crisp lines; the ball-carrier and selected player glow;
the sideline is populated with a real referee and the crowd shimmers; every player wears a correct
unique number; tackles never repeat and every downed man rises; the result reveal is a two-stage
broadcast stinger; weather affects the surface; Mental Readiness fills its column and passes AA.
**Verified via:** `render_verify.py` (all new clips), `dynasty-sim-qa` frame-QA + `analyze-app` (world/
motion), `visual-design-loop` + `accesslint` (UI), on-device eyeball on a real iPad for FPS.

---

## §3 — FLAGSHIP: Locomotion blend set

**The single biggest lift and the run at the Madden-2005 bar.** Today `setMoving`
(`SkeletalFigure.swift:311`) selects **only** `"run"` for every forward speed — `sprint` ships in the
bundle (confirmed present) but `clipName(for:)` never returns it; backpedal is the run clip
reverse-played (the "single-file coverage line" residual). Direction change is container-yaw + body-lean
(`run():1985`), not steps.

### Architecture decision — Option A (SceneKit discrete tiers). RealityKit NOT triggered.

SceneKit has **no parametric blend tree**. Three options were weighed:

| Option | Quality | Migration risk | Verdict |
|---|---|---|---|
| **A. Discrete speed-tier cross-fade (SceneKit)** | Good — reads as gait change; 0.3s dissolve at boundaries hidden by stride-sync continuity | **Low** — extends the proven `setMoving` cross-fade; keeps SCNIK foot-lock, ground clamp, ball-pin, camera rig untouched; reversible behind `useSkeletalFigures` | **CHOSEN** |
| B. Additive lean layer (`isAdditive`) | Adds turn-lean over base loco | Medium — additive clips finicky; turn-lean already procedural | Optional refinement only |
| C. RealityKit posing layer | Best — true `BlendTreeAnimation` | **High** — dual-renderer compositing over the SCNScene, or a multi-week full port of the 5735-ln `FootballFieldScene` that discards the working `SCNIKConstraint` foot-lock | **Defer — not triggered** |

**Why A is safe:** the choreographer→scene boundary is clean (`PlayChoreographer` produces positions/
timeline; only `FootballFieldScene`+`SkeletalFigure` pose). Tiers change *how a limb bends*, never
*where players go* — blocking, camera, HUD, ball-pin, and weather are all untouched. This is exactly the
"posing layer is separable" thesis the overhaul plan banks on. **Risk call:** the only real risk is
perceptible pops at tier boundaries and FPS with 22 skinned figures cross-fading; both are bounded and
measurable, and the whole thing is reversible behind the existing flag — so the RealityKit dual-renderer
/ full-port risk is not worth taking unless discrete tiers demonstrably fail the bar on device.

### Milestones (de-risk order)

- **F-1 · Wire the sprint clip (S) — do first, proves the tier mechanism.** Add a `.sprint` loco case +
  speed threshold in `setMoving`; measure its treadmill `runV0` (as run's 3.716 was measured) so
  stride-sync holds. Zero authoring — the clip already ships. **Verify:** `render_verify.py` grounded
  PASS (ships); on-device a breakaway visibly changes gait past the threshold, foot-plant holds.
- **F-2 · Walk + jog tiers (M).** Mixamo retarget (`mixamo_retarget.py`, leg-driven, arm-damp
  acceptable) → `walk`, `jog`; measure per-clip `runV0`; export. Select by `groundSpeedEMA`, cross-fade
  0.25-0.35s at boundaries, exact stride-sync inside each tier. **Verify:** grounded PASS; pre-snap
  shuffle and coverage read as walk/jog, not a slowed sprint.
- **F-3 · Real backpedal (M).** Mixamo retarget replaces the reverse-run cheat; drive the existing
  `.backpedal` case from the real clip. **Verify:** DBs backpedal facing the QB, break cleanly — fixes
  the single-file coverage line.
- **F-4 · Cut / plant footwork (M).** Fire `zigzag.juke` (unused pack segment) + optional Mixamo
  plant-and-cut as one-shot layered actions over loco (foot-lock suspended, like `juke_a`) when a
  route's heading change exceeds a threshold. Pair with a short gather/decel plant (2-frame IK — **pole
  targets required**, the knee-collapse lesson from the stance session). **Verify:** grounded PASS
  (game-angle render, mandatory); a route break shows a plant step, not a container-yaw slide.
- **F-5 · Snap-burst first step (S, ties to MED-5).** `hike.snap` for the center + a short additive
  load-and-drive so the line fires off the ball instead of a soft stand-up.

### Flagship Definition of Done

Distinct gaits at walk / jog / run / sprint with correct arm carriage; a real backpedal in coverage;
plant-and-cut footwork on route breaks; foot-plant holds through every tier boundary and every cut; no
jog-in-place, no single-file coverage. **Verified via:** `render_verify.py` batch (grounded PASS on all
new clips) + a `motion_profile` A/B video (old single-clip vs tiered) judged by `analyze-app`, and — the
gate that actually decides Option A vs C — **FPS held with 22 figures cross-fading on a real iPad, not
the sim.**

---

## §4 — Dependency graph & execution order

```
HOUSEKEEPING: restore playClockSetting=10 (after QA)    [independent, anytime]

QUICK WINS
  QW-1 tint merge ───────────────┬──► MED-4 number decal ─┐
   (SkeletalFigure.swift)        └──► FLAGSHIP (same file) │  merge-before-edit
  QW-3 apex/sky ──► QW-2 lighting ───► MED-1 field ──► MED-2 player rim
                         │                                  │
                         └──────────────────────────► MED-3 world life / HDRI
  QW-5a tokens ──┬──► QW-5b/c/d HUD ──► MED-6 stinger v2
                 ├──► (snap-bar restyle, folded into QW-5)
                 ├──► MED-8a Mental Readiness
                 └──► (card art, MED-adjacent)
  QW-6 camera beat sheet ──► MED-5 contact variety ──► MED-8b returner catch
  QW-4 kicker clip                                    [independent]

MEDIUM (Meshy items gated on MED-3 Step-0 key detection)
FLAGSHIP: F-1 (proves mechanism) → F-2/F-3/F-4 (author batch) → F-5
```

**Suggested order:**
1. **Session 1 (Quick Wins A):** QW-1 tint merge → QW-3 sky → QW-2 lighting → QW-4 kicker. All scene/
   asset, low-risk, immediately visible. Restore the play-clock when done.
2. **Session 2 (Quick Wins B):** QW-5a tokens → QW-5b/c/d HUD + reveal v1 → QW-6 camera beat sheet.
   Requires a fresh build to verify UI.
3. **Medium wave 1:** MED-1 field, MED-2 player rim, MED-4 number decal, MED-3a crowd shimmer (no key).
   Kick off MED-3 Step-0 key detection; if no key, queue free-asset fallback or defer props.
4. **Medium wave 2:** MED-5 contact variety (one Blender retarget batch + one `render_verify` gate run),
   MED-6 stinger v2, MED-7 weather, MED-8 mental readiness + returner catch.
5. **Flagship:** F-1 immediately (proves the tier mechanism, zero authoring), then the F-2/F-3/F-4
   Mixamo author-batch through one `render_verify` gate, then F-5. **Merge QW-1 before touching
   `SkeletalFigure.swift` for the Flagship.**

**Author-once batches (one Blender session, one gate run each):** (a) retarget the getups + 3 tackles +
zigzag.juke + wider kick windows + holder — all from existing pack takes; (b) the Mixamo leg-driven
batch — walk, jog, backpedal, block-shed.

---

## §5 — Definition of Done per phase (verification loops named)

| Phase | Done when | Verification loop |
|---|---|---|
| **Quick Wins** | 32-team colors, no "10"; soft cast shadow, players lift off bg; graded sky; readable kicker; one dominant HUD anchor, all text ≥4.5:1, kickoff chips gated, color-timed reveal; every play type has a distinct camera beat + 0.75s contact hold | `visual-design-loop` (UI build→screenshot→judge→iterate), `dynasty-sim-qa` frame-QA (scene/camera, 1 frame/0.5s), `render_verify.py` (kicker), `accesslint` (contrast), **on-device eyeball on a fresh build** |
| **Medium** | Turf relief + crisp lines; carrier/selection glow; populated sideline + real ref + shimmering crowd; unique on-mesh numbers; no repeated tackles + every man rises; two-stage stinger; weather wets the field; Mental Readiness fills its column | `render_verify.py --fall` (clips), `dynasty-sim-qa` + `analyze-app` (world/motion), `visual-design-loop` + `accesslint` (UI), **real-iPad FPS check** |
| **Flagship** | Distinct walk/jog/run/sprint gaits, real backpedal, plant-and-cut; foot-plant holds through boundaries/cuts; no jog-in-place, no single-file coverage | `render_verify.py` batch (grounded PASS), `motion_profile` A/B video → `analyze-app` judge, **22-figure FPS on a real iPad** (the Option-A-vs-C decider) |

**Cross-cutting gates (every phase):** no Codable/Engine changes (presentation only — the balance
workflow owns Engine); GPU work stays within the `scenekit-shader-vfx` TBDR budget (`half` default,
≤2 materials for gated effects, one downsampled transient post pass, **DoF replay-only**); every clip
passes `render_verify.py` before bundling; game-angle renders are mandatory (the stance-cross lesson);
perf is measured on a **real iPad**, not the simulator.

---

## Appendix — key files (absolute)

- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty/UI/Match/FootballFieldScene.swift` — scene, lighting (:5450), camera (:5402), field (:3998/:4025), stadium/crowd (:4449/:4556), ref (:4621), fog/sky (:5545), mesh-hold (:388), player build (:5178)
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty/UI/Match/SkeletalFigure.swift` — tint target, `setMoving` (:311), foot-lock, `fall()`, stances
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/.claude/worktrees/agent-a6152ef59de58bb7a/dynasty/dynasty/UI/Match/SkeletalFigure.swift` — tint source (cherry-pick, do not copy)
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty/UI/Match/CoachedGameView.swift` — HUD monolith, scoreboard (:502), situation (:648), snap bar (:1384), banners (:2370), reveal (:3632)
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty/UI/Match/PlayDiagramView.swift` — X&O card art
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty/UI/Common/Theme.swift` — tokens (add DSType/DSElevation/DSMatchMotion + remedial primitives)
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty/UI/Roster/GamePlanView.swift` — Mental Readiness (:663-763)
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty/UI/Match/PlayChoreographer.swift` — tackle/gang/burst choreography
- `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/tools/asset-pipeline/` — `render_verify.py` (gate), `strip_root.py --seat`, `rokoko_retarget.py`, `mixamo_retarget.py`, `pack_segments.json` (unused segments to mine)
