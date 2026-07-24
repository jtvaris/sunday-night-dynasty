---
name: scenekit-shader-vfx
description: >-
  Add GPU shader effects and VFX to the Dynasty SceneKit/Metal match view on
  iOS/iPadOS. Use when writing SceneKit shader modifiers (geometry/surface/
  lightingModel/fragment), a full SCNProgram (custom Metal vertex+fragment),
  or an SCNTechnique multi-pass post-effect; and for player/field visuals like
  rim/fresnel highlight on the selected player, team-color tint masks, toon/cel
  shading, selection outline, dissolve/spawn, hologram/scanline, turf, jersey
  number masking, or shader performance work. Also covers translating GLSL/HLSL
  shader ideas to Metal Shading Language (MSL) and Apple's Tile-Based Deferred
  Rendering (TBDR). Triggers: "shader modifier", "SCNProgram", "SCNTechnique",
  "Metal", "MSL", ".metal", "fragment/vertex shader", "fresnel", "rim light",
  "outline", "toon/cel", "dissolve", "hologram", "team color tint",
  "post-processing", "bloom", "GPU perf / half precision". NOT for the Blender
  asset/clip pipeline (use blender-game-asset-pipeline) and NOT for SwiftUI
  2D/HUD styling.
---

# SceneKit Shader & VFX (Dynasty)

The match view is **native SceneKit + Metal**, not Unity/Unreal/WebGL. Player
nodes are set up in `dynasty/dynasty/UI/Match/FootballFieldScene.swift` and the
skinned figure in `dynasty/dynasty/UI/Match/SkeletalFigure.swift`. There are no
custom shaders yet — this skill is for adding them the SceneKit way, tuned for
Apple's tile GPU.

## Pick the right injection level

| Need | Use | How |
|------|-----|-----|
| Tweak SceneKit's existing shading (tint, rim, UV tricks, vertex wobble) | **Shader modifier** | `material.shaderModifiers = [.surface: "…glsl…"]`. Cheapest, composes with SceneKit lighting/shadows. **Start here.** |
| Replace shading entirely for a material (custom lighting, stylized) | **SCNProgram** | `material.program = SCNProgram()` with MSL `vertexFunctionName`/`fragmentFunctionName` in a `.metal` file; bind data via `SCNProgramDelegate` / `handleBinding`. |
| Full-screen / multi-pass post FX (outline, bloom, color grade, selection glow) | **SCNTechnique** | `scnView.technique = SCNTechnique(dictionary:)` describing passes + fragment shaders. |

Shader modifiers are written in a **GLSL-like** dialect that SceneKit
transpiles to Metal; SCNProgram/SCNTechnique take **real MSL**. Entry points:
`.geometry` (per-vertex, modify `_geometry.position/normal/texcoords`),
`.surface` (per-fragment material inputs `_surface.diffuse` etc.),
`.lightingModel` (custom BRDF), `.fragment` (final color `_output.color`).

Pass parameters with `#pragma arguments` + KVC:
```glsl
#pragma arguments
float rimPower;
float3 teamColor;
#pragma body
// ... use rimPower, teamColor ...
```
```swift
material.setValue(2.5, forKey: "rimPower")
material.setValue(NSValue(scnVector3: teamRGB), forKey: "teamColor")
```
Textures bind as `SCNMaterialProperty(contents: image)` set for the same key.
Time-animate with the built-in `u_time` uniform.

## TBDR rules (Apple GPU — the perf that actually matters here)

The iPad GPU is tile-based deferred. Porting desktop/WebGL habits wastes it:
- **Default to `half` (16-bit)**; use `float` only for positions/depth/anything
  precision-critical. `half` doubles register occupancy and halves bandwidth.
- **No runtime branching on constants** — use **function constants** (SCNProgram)
  or separate materials/passes instead of `if (uUseNormalMap)` per fragment.
- **Bandwidth is the budget, ALU is cheap.** Minimize texture samples; pack masks
  into channels (e.g. R=team-tint mask, G=dirt, B=AO) rather than 3 textures.
- **Prefer memoryless/transient render targets** for SCNTechnique intermediate
  passes so tile memory never spills to DRAM.
- With ~22 skinned players on screen, a heavy per-fragment shader × full-screen
  overdraw is the real cost — keep the selected-player-only effects gated to one
  material, and post FX to a single cheap pass.
- Profile with **Xcode GPU capture / Metal shader profiler**, not print debugging;
  watch occupancy and per-pass timing.

## Common Dynasty effects (recipes in reference.md)

- **Selected-player rim/fresnel highlight** — `.surface` modifier, `pow(1 - dot(N,V), p)`
  added to emission; the single clearest "who's selected" cue.
- **Team-color tint via mask** — re-tint the `JERSEY`/`PANTS`/`HELMET` named slots
  (the Blender pipeline already names them) by lerping toward `teamColor` where a
  mask channel is set. Ties directly into `SceneKit re-tints by name`.
- **Toon / cel** — quantize `NdotL` through a ramp in `.lightingModel` for a
  stylized broadcast look; pair with an outline.
- **Selection / possession outline** — inverted-hull (front-cull, push verts along
  normal) as a second material pass, or a Sobel-on-depth `SCNTechnique` for a clean
  screen-space outline.
- **Dissolve / spawn-in** — noise texture threshold against `u_time`, `discard`
  below it, emissive edge band; good for substitutions / injury fade.
- **Turf / field** — tri-planar or UV-tiled grass with mow-stripe mask; cheap.

## Deep reference

`reference.md` holds the concrete snippets: shader-modifier skeletons per entry
point, the fresnel/team-tint/toon/dissolve modifiers, an SCNProgram MSL
vertex+fragment template with `SCNProgramBufferStream`/binding, an SCNTechnique
outline/bloom pass dictionary, the GLSL→MSL translation cheatsheet
(`texture2D`→`.sample`, `mix`→`mix`, `fract`→`fract`, swizzles), and iOS texture
formats (ASTC preferred, keep BC* off iOS).

---

### Attribution & licenses

Synthesized and re-framed for SceneKit/Metal on iOS from:
- **majiayu000/claude-skill-registry** (MIT) — `metal-shader-expert` (upstream
  **erichowens/some_claude_skills**, MIT): the TBDR rules, `half`-vs-`float`,
  function-constant specialization, and GPU-debug guidance are adapted from it.
  Its `references/*.md` (PBR/noise/debug MSL) were NOT in the registry snapshot, so
  those snippets here are re-derived. Also drew the GLSL mental model from the
  registry `shader-fundamentals` skill and the effect *concepts* (toon ramp,
  inverted-hull outline, fresnel) from `shader-techniques` — whose Unity/HLSL
  `Shader{}`/`CGPROGRAM` code was **rejected** (Unity-only) and re-expressed as
  SceneKit shader modifiers / MSL.
- **DavinciDreams/Agent-Team-Plugins** `teams/3d-design` (no LICENSE file in repo)
  — iOS-relevant texture-format notes (ASTC/PVRTC) were **paraphrased**, not copied.
- Rejected wholesale: Three.js/R3F/WebGPU/Godot/Unity shader skills from the
  registry (wrong platform).

No shader code currently exists in the project; these are additions, not edits.
