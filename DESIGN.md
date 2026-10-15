---
version: 1.0
name: Liquid Glass
description: >-
  A definition of the "liquid glass" material for people and language models who have to build it. Frosted glass blurs and tints what is behind it. Liquid glass is a thin lens: a clear, flat centre where content passes through almost untouched, and a narrow curved rim where the background is refracted (displaced, magnified, colour-split) and a specular highlight catches the light. The whole look lives in the last few pixels at the edge. Built and verified on a KDE Plasma 6 top bar; the model is platform-neutral.

material:
  centre:
    transparency: 0.82          # 1 - fill alpha. 0.90+ reads as "nothing there", 0.70- reads as a card
    fill: "#000000"
    fill-alpha: 0.18            # dark fill on a light wallpaper. Flip to white 0.08 for a dark wallpaper. Painted by the panel theme on top of the glass; the effect's own TintColor stays 0
    blur-radius: low            # 1 on a 1-15 scale: one half-resolution Kawase pass, offset 1.5. Blur only hides pixel noise; it must not fog the centre
    saturation: 1.0
  rim:
    edge-band: 14px             # width of the region that bends, at 2.5x display scale (~5.6 logical px)
    profile: steep-at-edge      # ours: w(x) = 1 - sqrt(1 - smoothstep(x)), x = 1 at the edge, 0 at the band's inner end; w is the tilt and displacement weight. Web ports use the convex squircle (1 - (1-x)^4)^(1/4) instead. Both rise fast at the edge and flatten inward
    refraction-index: 1.7       # our setting 14 / 20 + 1; browser ports use 1.45-1.5. In our shader the index only picks the direction; displacement is w * band * (1 + 14/20), about 24px at the silhouette, inward
    dispersion: 0.06            # red bends most, blue least, as a fraction of the displacement. Setting 4 -> 0.2 -> x0.3 = 0.06. 0 = off, 0.15 (setting 10) = rainbow
    specular-width: 1.2px       # x strength = 0.96px core, visible to about 2.9px
    specular-strength: 0.8      # 0-2. Thin white line that follows the silhouette
    light-angle: none           # our shader has no light vector. A position mask brightens the top-right and bottom-left corners, dims the top-left and bottom-right, about half strength elsewhere. Web ports use a fixed light at -55deg
  shape:
    corner-radius: 15px         # logical; pill = radius >= height / 2
    corner-curve: quadratic     # not a circle. Panel masks use quadTo(); a circle of 0.85 R matches it best
  shadow: none                  # a pill floating over wallpaper casts none. Thick sheets over content may
  border: none                  # the specular rim is the border. A drawn 1px line kills the effect

anti-material:                  # what liquid glass is NOT
  frosted: "blur 20px + white 0.2 + 1px border"      # glassmorphism, 2020
  neon: "edge lighting / glow added to the fill"     # blows the rim out to white
  card: "fill alpha above 0.35"                      # opaque enough that refraction is invisible
  flat-rim: "one glass shape around a group of pills" # bends only the group's outer edge

layout:
  pill-height: 42px             # 48 panel - 2 x 3 margin
  pill-padding-x: 10px
  pill-gap: 8px
  panel-inset-y: 6px
  maximized-mode: "flat, opaque, square, 30px"       # glass is for floating chrome; over a window it goes solid
---

## Overview

Liquid glass is Apple's name (WWDC 2025) for a UI material that "dynamically bends, shapes, and concentrates light". Older materials scattered light, which is why they were called frosted. This one is a lens.

Three things make it read as glass, in this order of importance:

1. A clear centre: the wallpaper or content behind the element is visible, sharp, and barely tinted. If the centre is foggy, you have frosted glass.
2. A curved rim that refracts: in a band a few pixels wide along the silhouette, the background is pushed outward or inward, slightly magnified, and split into colour fringes. Straight edges bend a little; corners and round ends bend the most. This is what people mean by "the edge looks like a water droplet".
3. A specular highlight on the rim: a thin bright line, brightest on the side that faces the light, fading on the far side. It replaces the border; there is no drawn outline.

Everything else (adaptive tint, shadow that darkens over text, morphing between shapes, glow on touch) is refinement on top of these three. With all three in place it reads as liquid glass even when static. Without the rim, adding blur, transparency or animation does not make it read as glass.

## Why language models get it wrong

Most training data about "glass UI" is glassmorphism: `backdrop-filter: blur(20px)`, a translucent white fill, and a 1px white border. That recipe is frosted glass. Asked for liquid glass, a model usually produces the same recipe with more blur and a gradient border, then calls it done.

The mistake is structural. Blur and transparency operate on the whole surface uniformly. Liquid glass is non-uniform: the centre does almost nothing and the rim does everything. A model that thinks in surface properties (opacity, blur, colour) cannot express it. It has to think in a height profile across the edge and derive everything from that.

Our own first attempt made this mistake. See "Iteration log" at the end.

## The optical model

Treat the element as a slab of glass lying flat on the background, with a bevelled edge.

### Height profile

Define `x` as the distance from the silhouette inward, normalised so `x = 0` at the edge and `x = 1` at the inner end of the edge band. Height:

- Flat centre: `h = 1` for everything past the band.
- Band: `h(x) = (1 - (1 - x)^4)^(1/4)`. This is the convex squircle. Apple's curves and the web ports use it because a circular dome `sqrt(1 - (1-x)^2)` makes a hard transition where the band meets the centre, and a squircle keeps the refraction smooth when the shape is stretched into a rectangle.
- Our shader does not compute a height at all. It computes a weight `w = 1 - sqrt(1 - smoothstep(edgeFactor))`, where `edgeFactor` is 1 at the silhouette and 0 at the inner end of the band (`RefractionNormalPow` 2 maps to exponent 1). That is a parabolic arc with a vertical tangent at the edge. `w` is used directly as the normal tilt and as the displacement weight. It is a different curve from the squircle and gives the same visual result: steep at the edge, flat inside.
- Alternatives that also read as glass: a concave bowl (`1 - convex`) which diverges the rays, or a "lip" that blends the two.

The surface normal is the derivative of `h`, rotated 90 degrees. Flat centre: normal points straight up, no bend. Band: the normal tilts outward, more steeply near the edge.

### Refraction

Snell's law, one refraction event, viewer looking straight down: `sin(theta_out) = sin(theta_in) / n`. With `n` between 1.45 and 1.7, a ray hitting the tilted band is bent toward the surface normal, so the sample point moves along the normal by a distance proportional to `tan(theta)` and the slab thickness.

What this produces on screen:

- Centre: displacement 0. The background is sampled where it is.
- Band: displacement grows from 0 at the inner end to its maximum at the edge, along the local normal. On a straight edge the background slides sideways. On a corner it is pulled toward the corner, so the round end of a pill shows a small magnified copy of what is just outside it. That magnified copy is the droplet look.
- The last pixel: the highest displacement, plus the specular line.

Displacement is stored as a 2D vector field (web: `feDisplacementMap` with X in red, Y in green, neutral 128; shaders: computed per fragment from the signed distance to the rounded rectangle).

### Dispersion

Red bends most, blue least. Sample the three channels at three displacements: `R at d * (1 + f)`, `G at d`, `B at d * (1 - f)`, with `f` between 0.05 and 0.15 of the displacement. Zero fringing looks like plastic. Heavy fringing looks like a broken monitor. On a 14px band we use `f` = 0.06: setting 4, divided by 20, times the shader's 0.3. Only the refracted part of the displacement is split, so red and blue separate by about 0.6px at the edge.

### Specular rim

The web ports take the same normal and dot it with a fixed light direction (top-left, about -55 degrees, is the convention). Where the dot product is high they add a thin bright line 1 to 2 px wide along the silhouette; where it is low, almost nothing. That gives an arc of light on the upper-left of every pill and a faint one on the lower-right.

Our shader has no light vector. It draws a white ring about 1px wide (peak 1 to 1.5px inside the silhouette, gone by 3px) and weights it by smoothsteps on the fragment's position in the box: near full strength at the top-right and bottom-left corners, about half along the edges and round ends, near zero at the top-left and bottom-right corners. The pattern is symmetric about the pill's centre. Either approach works; what matters is that the rim is uneven. A ring of constant brightness reads as an outline, not as lit glass.

Do not add light to the fill. "Edge lighting" that brightens the whole band turns the rim into a white neon tube and destroys the refraction under it.

### Blur, tint, saturation

- Blur radius stays small. Its only job is to soften pixel noise so the refraction does not look like a sharpening filter. If the centre reads as foggy, the blur is too high.
- Tint is a flat fill at low alpha. Over a light background, a dark tint at 0.15 to 0.2 keeps text readable. Over a dark background, a white tint at 0.06 to 0.1 lifts the pill off the wallpaper. Apple's adaptive version picks per element and per moment; a static choice per wallpaper is enough.
- Saturation 1.0. Boosting it is a glassmorphism habit and makes the centre look dyed.

### Shape

- Pills: corner radius equal to or larger than half the height, so both ends are full semicircles. The refraction is strongest there.
- Concentric corners: an element inside another rounded element takes `inner radius = outer radius - padding`, never the same radius. Mismatched curves read as a sticker.
- Corners are not necessarily circular. Plasma's panel masks draw them with a quadratic curve. A circle of `0.85 x` the curve's size matches its silhouette closely; a circle of the full size overshoots and the rim floats off the corner. Whatever the mask uses, the glass shape must match it to the pixel, or the rim sits inside or outside the visible edge.

## Anatomy of one pill

Cross-section from the outside in, at 2.5x display scale, our numbers:

| px from edge | what happens |
| --- | --- |
| 0 to 2.9 | specular line, peak at about 1.2. Brightest toward the top-right and bottom-left corners, faint at the other two |
| 0 to 14 | refraction band. Displacement falls from about 24px to 0 following `1 - sqrt(1 - smoothstep(edgeFactor))`, always inward. Colour fringes visible at the outer third |
| 14 to centre | clear glass. Background sharp, blur 1, dark fill at 0.18 |

Nothing else: no shadow, no drawn border, no inner highlight, no gradient fill.

## Layering rules

From Apple's guidance; they hold on any platform.

- Glass is for the layer that floats above content: bars, docks, toolbars, popovers, controls. It is not for content. A list, a card grid, or a text block made of glass has nothing to refract and becomes noise.
- No glass on glass. A glass button inside a glass bar does not get a second glass; it gets a flat fill or a tint on top of the one glass.
- Things placed on glass use fills and opacity, not more material.
- Glass needs something behind it to bend. A panel with its own opaque background under the pills defeats the effect. The panel is transparent; only the pills are glass.
- Over a maximized window, glass steps aside: the bar becomes flat, opaque and square. Refraction over a document is distraction, and there is no wallpaper to refract.

## Motion and state, when you have them

Static is enough for the material to read. When animation is available:

- Elements materialise by ramping the refraction from 0, not by fading alpha. Alpha fades look like a screenshot fading in.
- Touch or hover: brighten from the contact point outward, and scale by a few percent. The material is "gel-like", it flexes.
- Neighbouring pills that move close enough merge like drops and split when they part. The silhouette is a single rounded shape while merged.
- Menus that open from a glass button grow from the button's shape into the menu's shape; the glass gets thicker (more refraction, deeper shadow) as the shape gets bigger.
- Accessibility: "reduce transparency" makes it frostier and more opaque; "increase contrast" swaps it for black or white with a solid border; "reduce motion" removes the flex.

## Parameters that worked, and their limits

Measured on Plasma 6.6, Wayland, 2.5x scale, a soft blue cloud wallpaper. Names in parentheses are the Glass KWin effect settings.

| parameter | value | too low | too high |
| --- | --- | --- | --- |
| fill | black 0.18 | 0.08 white: text unreadable over light clouds | 0.35: reads as a solid card, refraction invisible |
| refraction strength (`RefractionStrength`) | 14 (= n 1.7) | under 8: edge looks merely blurred | 20+: vertical streaks. Displacement is inward, so on a straight top or bottom edge the band is a vertically stretched copy of the columns under it, and the stretch grows with strength (24px at 14, 28px at 20) |
| edge band (`RefractionEdgeSize`) | 1.4 (= 14px) | under 1: the bend is one pixel and reads as a border | 2.5+: the centre shrinks and the pill looks like a bubble |
| dispersion (`RefractionRGBFringing`) | 4 (= f 0.06) | 0: plastic | 10 (= f 0.15): rainbow edges |
| specular (`RimSpecular`, width 12, scale 8) | on | off: no silhouette, pill floats off the wallpaper | scale 15+: a white ring |
| edge lighting (`EdgeLighting`) | **off** | | on: every pill edge blows out to solid white |
| blur (`DockBlurStrength`) | 1 | 1 is the minimum | 3+: frosted |
| shadow | off | | any: sticker on wallpaper |
| corner radius | 15 logical | | the effect's own `DockCornerRadius` must stay 0; a non-zero value clips the whole panel window and rounds a full-width bar |

## Testing that it is real

These two checks are cheap, and both saved us.

1. The loud tint test: set the glass fill to opaque red for one frame. If the pills turn red, the glass shader is drawing on them. If not, whatever you are looking at is coming from another layer. A blur effect can report itself as loaded and draw nothing, and a border from the panel theme looks enough like a rim to fool a screenshot review.
2. Zoom the round end: at 3x to 4x, the specular line must follow the semicircle and the background inside the band must be visibly displaced compared to the pixels just outside. If the line runs straight across the end, the glass shape and the mask shape disagree.

Screenshots of soft wallpapers hide refraction. Test over something with lines or text behind the pill.

## Iteration log: where it went wrong and what fixed it

The order matters. Each step looked finished at the time.

1. Started as glassmorphism. Panel Colorizer only: white fill 0.08, blur, 1px white border, drop shadow. It was transparent and had a rim, but it was frosted glass: nothing bent anywhere, and nothing in that toolset can produce a bend. Lesson: transparency plus border is not the material; a compositor-level refraction shader is required.
2. Installed the Glass KWin effect and "verified" it by screenshot. The pills had a rim, but it was still the Panel Colorizer border; the effect was loaded and drawing nothing. The log said `Failed to read shader ":/effects/glass/generated/vertex_core.vert"` and `glUseProgram(program 7 not linked)` on every frame; that line had been dismissed as noise. Lesson: a visible rim proves nothing. Run the loud tint test.
3. Root cause: shader file names. KWin 6.6 asks for `*_core.vert` and `*_core.frag`; upstream only shipped the un-suffixed files. Fixed by aliasing them in the resource file. Then nothing changed on screen, because KWin keeps an already-loaded effect's binary in memory. It took a re-login. Lesson: after reinstalling a compositor effect, restart the compositor before judging anything.
4. First real render was neon. With `EdgeLighting` on, every pill edge went solid white and read as glow. With it off and a thin specular rim instead, the edge bend became visible for the first time, and the bar started to read as liquid glass.
5. Only the bar's outer edge bent. Upstream draws one glass shape around the whole panel window. A bar of eight pills got refraction on its top and bottom and at its far left and right, and nothing at any pill's round end. Patched the effect to split the panel's blur area into islands and draw one glass shape per island. The round ends started bending.
6. Refraction streaked at strength 20. The displacement is inward, so along a straight top or bottom edge every column of the band is a stretched copy of the column beneath it, and at 20 the stretch is 28px on a 14px band. 14 stays clean. Lesson: on a straight edge, inward refraction is a vertical stretch; keep it shorter than the band is wide, or hide it with a rim.
7. Subtraction. Removed the drop shadow, then the 1px border: the specular rim was already doing the border's job and the drawn line sat on top of it. Then darkened the fill from white 0.08 to black 0.18 because the green percentage text had become unreadable. Lesson: once the rim exists, every other edge decoration competes with it.
8. Maximized mode rounded the whole bar. The effect's `DockCornerRadius` clips the entire panel window, so the flat bar got round corners. Set it to 0 and measured each pill's roundness from its own shape instead. The first measurement took the inset of the top pixel row as the radius and got about 20px where the real value was 37px, so the rim ran straight across the round ends. The mask draws corners with a quadratic curve, not a circle; solving that curve for the observed inset and using 0.85 of it as a circle radius put the rim back on the silhouette.

The material worked from step 4 and the geometry from step 8. Steps 1 to 3 produced nothing that was liquid glass, and steps 1 and 2 were reported as done.

## Recipe by platform

**Compositor shader (what this repo does).** Per fragment: signed distance `d` to the rounded rectangle; `edgeFactor = 1 - clamp(|d| / band, 0, 1)`; weight `w = 1 - sqrt(1 - smoothstep(edgeFactor))`; normal = SDF gradient tilted by `w`; `refract()` a straight-down ray with `n` for the direction, then displace inward by `w * band * (1 + strength)`; sample the background there, three times for dispersion; add the position-weighted white rim; mask by the SDF. The tint fill is painted by the panel theme above the glass, not by the shader. Draw one such shape per island, never one per window.

**Web.** `backdrop-filter: blur(1px) saturate(1)` for the centre; an SVG filter with `feDisplacementMap` whose map encodes the squircle displacement in R and G, applied as `backdrop-filter: url(#glass)` (Chromium only as of 2026); a second pass for the specular rim blended with `screen`; `border: none`; `box-shadow: none`. Reference implementations: kube.io's article, `eirasmx/webglass` (defaults: `n` 1.45, bezel 0.28 of the short side, light -55 degrees).

**Static mockups (Figma, image generation).** Draw the background; over it a rounded rectangle at fill 0.15 to 0.2 with no stroke; along the inside of the edge, a 10 to 15 px band where the background is copied, scaled up 5 to 10 percent toward the edge, and offset outward; over that, a 1px white line at 60 to 80 percent that is brightest on one arc and fades toward the opposite one (the web convention lights the upper-left; ours happens to light the top-right and bottom-left). No blur over 2px. No shadow.

## Do's and don'ts

Do:
- Keep the centre clear and sharp.
- Put all the work in a band under 15 px at 2.5x (about 6 logical px).
- Use a profile that is steep at the edge and flat inside: the squircle, or our `1 - sqrt(1 - smoothstep(x))`.
- Light from one fixed direction; specular only on the rim.
- Match the glass shape to the mask shape to the pixel.
- Go flat and opaque over a maximized window.
- Prove the shader draws with a loud tint before tuning anything.

Don't:
- `blur(20px)` anything.
- Draw a border. The rim is the border.
- Add glow, edge lighting, or inner shadow to the fill.
- Cast a drop shadow from a thin pill.
- Raise saturation.
- Make content out of glass, or stack glass on glass.
- Round a group of pills with one shape.
- Trust a screenshot over a soft wallpaper.

## Sources

- Apple, WWDC25 session 219 "Meet Liquid Glass": lensing, regular and clear variants, layering, tinting, accessibility.
- Apple Newsroom, June 2025: "translucent ... reflects and refracts its surroundings", "dynamically reacts to movement with specular highlights", concentric with hardware corners.
- kube.io, "Liquid Glass in the Browser: Refraction with CSS and SVG": height profiles, Snell's law with `n` 1.5, why the centre stays undistorted, displacement-map encoding.
- `eirasmx/webglass`: defaults `n` 1.45, bezel 0.28, light -55 degrees; profiles squircle, circle, lip, concave.
- `4v3ngR/kwin-effects-glass` and this repo's fork branch `per-pill-glass`: the shaders (`glass.glsl`, `snells-glass.glsl`, `rim.glsl`) and the per-island patch these numbers come from.

## Known gaps

- No adaptive tint or adaptive shadow. The fill is one static colour per wallpaper.
- No morphing, merging, or touch glow. Plasma panels do not animate widget shapes.
- The background texture is the bounding box of the whole panel's blur area: one row high, all pills wide. Displacement is inward only, so nothing above or below the row is ever shown at an edge. Real lensing would bring in what is just outside the pill.
- Corner rounding is inferred from the blur mask. A mask drawn with a different curve needs a different fit than 0.85.
- Verified over one wallpaper family (soft clouds, light blue). Busy or high-contrast wallpapers may want fill 0.25 and dispersion 2.
