# SceneKit Shader & VFX — Reference

Concrete snippets for Dynasty's SceneKit/Metal match view. Shader **modifiers**
are GLSL-like (SceneKit transpiles to Metal); **SCNProgram**/**SCNTechnique** use
real MSL. Materials/nodes live in `FootballFieldScene.swift` /
`SkeletalFigure.swift`.

---

## 1. Shader-modifier skeleton (start here)

```swift
material.shaderModifiers = [
    .surface: surfaceSrc,          // per-fragment material inputs
    // .geometry / .lightingModel / .fragment also available
]
material.setValue(2.5, forKey: "rimPower")
material.setValue(NSValue(scnVector3: SCNVector3(0.05, 0.2, 0.8)), forKey: "teamColor")
```

Entry-point I/O you can read/write:
- `.geometry` → `_geometry.position`, `.normal`, `.texcoords[0]` (vertex stage).
- `.surface` → `_surface.diffuse`, `.emission`, `.normal`, `.metalness`,
  `.roughness`, `.position` (view space), `.view`, `.geometryNormal`.
- `.lightingModel` → accumulate into `_lightingContribution.diffuse/specular`.
- `.fragment` → `_output.color` (final).
Built-ins: `u_time`, `u_inverseViewTransform`, `scn_frame.*`. Declare custom
uniforms under `#pragma arguments`.

---

## 2. Selected-player rim / fresnel (the key selection cue)

`.surface` modifier — adds a view-dependent glow to emission:

```glsl
#pragma arguments
float  rimPower;
float3 rimColor;
#pragma body
float3 N = normalize(_surface.normal);
float3 V = normalize(_surface.view);          // fragment->camera, view space
float  fresnel = pow(1.0 - saturate(dot(N, V)), rimPower);
_surface.emission.rgb += rimColor * fresnel;
```
```swift
sel.setValue(3.0, forKey: "rimPower")
sel.setValue(NSValue(scnVector3: SCNVector3(1.0, 0.85, 0.2)), forKey: "rimColor")
```
Gate it to the currently selected player's materials only; clear on deselect.
`saturate(x)` = `clamp(x,0,1)` (SceneKit provides it; in raw MSL use `saturate`).

---

## 3. Team-color tint via mask (ties to the named slots)

The Blender pipeline names slots `JERSEY/PANTS/HELMET/…` and SceneKit re-tints by
name. To recolor per-team without new textures, lerp toward `teamColor` where a
mask channel says "tintable":

```glsl
#pragma arguments
float3 teamColor;
#pragma body
// mask packed in a control texture, e.g. R = tint amount
float amt = _surface.ambientOcclusion.r;      // or bind a dedicated mask sampler
_surface.diffuse.rgb = mix(_surface.diffuse.rgb, _surface.diffuse.rgb * teamColor, amt);
```

Bind a dedicated mask with `SCNMaterialProperty(contents: maskImage)` set for a
`#pragma arguments` `texture2d`/`sampler` key when you don't want to reuse an AO
channel. Pack multiple masks into R/G/B/A to save bandwidth (TBDR rule).

---

## 4. Toon / cel (stylized broadcast look)

`.lightingModel` — quantize diffuse through a stepped ramp:

```glsl
#pragma body
float ndotl = saturate(dot(normalize(_surface.normal),
                           normalize(_lightingContribution.direction)));
float bands = 3.0;
float toon  = floor(ndotl * bands) / bands;   // or sample a 1D ramp texture
_lightingContribution.diffuse *= toon;
```

Pair with the outline (§6) for a full cel look.

---

## 5. Dissolve / spawn-in (substitution, injury fade)

`.fragment` (or `.surface`) — threshold a noise texture against `u_time`, discard
below it, glow the edge:

```glsl
#pragma arguments
float dissolve;      // 0 = solid, 1 = gone
#pragma body
float n = _surface.ambientOcclusion.r;         // or a bound noise sampler
if (n < dissolve) { discard_fragment(); }
float edge = smoothstep(dissolve, dissolve + 0.06, n);
_output.color.rgb += float3(1.0, 0.5, 0.1) * (1.0 - edge);
```
Animate `dissolve` from Swift with a `CABasicAnimation`/`SCNAction` on the KVC key.

---

## 6. Selection / possession outline

Two options:

**A. Inverted-hull (per-object, cheap, chunky):** a second material that
front-culls and pushes verts along their normal. Via SCNProgram or a `.geometry`
modifier on a duplicated node:
```glsl
// .geometry modifier on the outline copy
#pragma arguments
float outlineWidth;
#pragma body
_geometry.position.xyz += normalize(_geometry.normal) * outlineWidth;
```
Set that material's `cullMode = .front` and a flat emissive color.

**B. Screen-space Sobel on depth (SCNTechnique, clean):** full-screen pass that
edge-detects the depth buffer — one pass, uniform width, works for any silhouette.
See §8.

---

## 7. SCNProgram (full custom MSL for one material)

`.metal` file (real MSL):
```metal
#include <metal_stdlib>
using namespace metal;

struct VIn  { float3 position [[attribute(SCNVertexSemanticPosition)]];
              float3 normal   [[attribute(SCNVertexSemanticNormal)]];
              float2 uv       [[attribute(SCNVertexSemanticTexcoord0)]]; };
struct VOut { float4 position [[position]]; half3 normal; float2 uv; };
struct NodeBuffer { float4x4 modelViewProjectionTransform;
                    float4x4 modelViewTransform; };            // per-node, bound by name

vertex VOut player_vertex(VIn in [[stage_in]],
                          constant NodeBuffer& scn_node [[buffer(0)]]) {
    VOut o;
    o.position = scn_node.modelViewProjectionTransform * float4(in.position, 1.0);
    o.normal   = half3(normalize((scn_node.modelViewTransform * float4(in.normal,0)).xyz));
    o.uv       = in.uv;
    return o;
}
fragment half4 player_fragment(VOut in [[stage_in]],
                               texture2d<half> albedo [[texture(0)]],
                               sampler s [[sampler(0)]]) {
    half3 base = albedo.sample(s, in.uv).rgb;     // half precision — TBDR-friendly
    half  lit  = max(0.0h, dot(in.normal, half3(0,1,0)));
    return half4(base * (0.3h + 0.7h * lit), 1.0h);
}
```
```swift
let p = SCNProgram()
p.vertexFunctionName = "player_vertex"
p.fragmentFunctionName = "player_fragment"
material.program = p
material.setValue(SCNMaterialProperty(contents: albedoImage), forKey: "albedo")
// bind custom per-frame data via p.handleBinding(ofBufferNamed:…) or SCNProgramDelegate
```
SceneKit auto-fills `scn_node`/`scn_frame` structs by name. Use **function
constants** for on/off features instead of runtime `if`.

---

## 8. SCNTechnique (multi-pass post FX)

Selection glow / outline / bloom as full-screen passes. Dictionary (usually a
plist) wires pass order, targets, and fragment shaders; intermediate targets
should be transient to stay in tile memory:

```swift
let technique: [String: Any] = [
  "passes": [
    "outline": [
      "draw": "DRAW_QUAD",
      "inputs": ["depth": "DEPTH", "colorSampler": "COLOR"],
      "outputs": ["color": "COLOR"],
      "metalVertexShader": "quad_vertex",
      "metalFragmentShader": "sobel_depth_outline"   // in a .metal in the bundle
    ]
  ],
  "sequence": ["outline"],
  "targets": [:]                                     // add transient targets for bloom chains
]
scnView.technique = SCNTechnique(dictionary: technique)
```
For bloom: bright-pass → separable blur (H then V, downsampled) → composite —
each an extra quad pass; downsample aggressively (bandwidth budget).

---

## 9. GLSL/HLSL → MSL / SceneKit cheatsheet

| GLSL / HLSL | SceneKit modifier | MSL (SCNProgram) |
|-------------|-------------------|------------------|
| `texture2D(t,uv)` / `tex2D` | `texture(sampler, uv)` | `t.sample(s, uv)` |
| `gl_FragColor` / `SV_Target` | `_output.color` | function `return half4(...)` |
| `mix(a,b,t)` / `lerp` | `mix` | `mix` |
| `fract` / `frac` | `fract` | `fract` |
| `clamp(x,0,1)` / `saturate` | `saturate` | `saturate` |
| `mod(x,y)` | `mod` | `fmod` |
| `varying` / `v2f` | (auto interp) | struct with `[[stage_in]]` |
| `uniform` | `#pragma arguments` + KVC | `constant T& [[buffer(n)]]` / `[[texture(n)]]` |
| `vec3` / `float3` | `float3` / `half3` | `float3` / `half3` (prefer `half`) |
| time uniform | `u_time` | bind `scn_frame.time` |

MSL notes: half literals take an `h` suffix (`0.5h`); `discard` is
`discard_fragment()`; column-major matrices like GLSL; texture+sampler are
separate objects (not a combined `sampler2D`).

---

## 10. iOS texture formats

- **ASTC** is the modern iOS/iPadOS compressed format — use it (variable block
  size trades size vs quality). PVRTC is the legacy Apple format; only for old
  targets. **BC1–7 / DXT are desktop-only — do not ship them on iOS.**
- Generate mipmaps for anything viewed at distance (`SCNMaterialProperty.mipFilter`).
- Normal maps: store in a linear (non-sRGB) texture; keep base color sRGB.
- Channel-pack masks (team-tint / dirt / AO in R/G/B) to cut sampler count — the
  single biggest TBDR bandwidth win for 22 on-screen players.
