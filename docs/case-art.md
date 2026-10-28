# The Loadout case: art and motion

The case in the drop sheet, the Library toast and the drag-over highlight is Maddy's final art
(`Loadout/Assets.xcassets/LoadoutCase/`, vector PDFs with "Preserve Vector Data"). Only the
drawing is hers; the motion, the interior, the shadow and the progress fill are code.
`layers.json` (next to this file) is her layer map.

## Layers (back to front)

| Imageset | Rig group | Notes |
|---|---|---|
| LoadoutCaseContactShadow | ground | squashes with the drag-over bounce |
| LoadoutCaseHandle | lid | handle fold [424,395]/[600,395] not animated in v1 |
| LoadoutCaseLid | lid | hinge y 498 (icon) = y 266 (case artboard) |
| LoadoutCaseRailsBody | body | |
| LoadoutCaseRailsLid | lid | |
| LoadoutCaseColorBar | body | the progress bar (see below) |
| LoadoutCaseLatchLeftBase / RightBase | split | top half rides with the lid, bottom half with the body |
| LoadoutCaseLatchLeftLeverClosed / RightLeverClosed | latch | pivots [356,540] / [668,540] icon = (164,308) / (476,308) artboard |
| LoadoutCaseLatchLeftLeverOpen / RightLeverOpen | latch | swapped in past 90 degrees of the flip |

Not used in the app: `background` and `icon-overlay` (icon only).

Case artboard: 640 x 560, which is the 1024 icon space minus (192, 232).

## How it moves

- `CaseMotion.swift`: pure maths and `CaseDriver` (timings, easing, events). Unit tested.
- `CaseArt.swift`: draws a `CasePose` from Maddy's layers.
- `CaseStage.swift`: the TimelineView, cards and haptics; `CaseDropTarget` for drag-over.

Lid: the lid group tilts back about its top edge (`rotation3DEffect` on x, perspective 0.35)
and lifts. Between the open lid and the seam a code-drawn dark interior shows (there is no
interior layer).

Latches: each closed lever flips about its pivot; past 90 degrees the open lever is shown.

Progress bar: the color-bar layer is drawn as-is, and a Canvas clipped to its pill paints the
unfilled part with the well colour (#111A2E) and a lit edge, so the gradient is revealed left to
right. The glint is a white band clipped to the same pill. The fill only ever follows real
progress: the file operator reports bytes done (`FileOpProgress`), and the bar never moves
ahead of that or of the cards that have landed.

Shadow: Maddy's vectors carry none; the front group has a SwiftUI drop shadow
(black 18 %, radius 6, y 5 at artboard scale) and her contact-shadow layer sits under it.

Top-corner seam: the lid and the 90 % opaque lid rails antialias along the same rounded corner,
so the lid's white edge can glow through. The lid is masked 1.5 units in under the rails
(`lidCornersTucked`), which hides its edge there; between the rails it keeps its full edge.

Reduce Motion: no flights, flips or bounces; a 0.3 s crossfade between the open and shut case
while the bar fills (or drains) with the real progress.

## Film

Debug builds render the animation offscreen: `open -g -j -n --env LOADOUT_RENDER_CASE=/folder
Loadout.app` writes PNG frames, stills and the real progress traces, without a window or focus.
