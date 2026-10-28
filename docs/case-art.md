# The Loadout case: art and motion

The case in the install strip, the Library toast and the drag-over highlight is Maddy's final art
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

## How it moves: Maddy's "case-sort"

The motion follows Maddy's approved case-sort animation (`loadout-case-sort.html` and its
motion notes), the install/uninstall counterpart of Lodge's wagon strip. It plays in a
492 x 153 pt strip: a 41 pt header (icon, verb, title, "n of N · p%" or the Restart/Update
Lists badge) over a 112 pt scene that is always dark. The strip sits in the install sheet
above the footer, and the same strip on `.regularMaterial` is the Library toast.

Install: the latches flip and the lid opens; cards rise from the desk and arc into the case,
each landing fills its group's segment of the bar; the lid closes with a squash and bounce,
the latches click shut (left, then right, with a haptic each), a glow plays and the label
turns green. Uninstall plays the story backwards.

- `CaseSortMotion.swift`: her clocks and easing, the stage geometry (`CaseSortStage.strip`
  is her `C2S`), the card budget and bar segments (`CaseSortLayout`) and `CaseSortDriver`,
  which turns real progress into the story. Unit tested (`CaseSortTests`).
- `CaseSortPainter.swift`: one `Canvas` drawing her layer order: background, sky glow, desk
  shadows, cards, case glow, case back and lining, front (lid squash), bar, levers, sparkles.
- `CaseSortStrip.swift`: header, strip, TimelineView engine, haptics, `CaseToast` and
  `CaseDropTarget` (the case alone, opening, for drag-over).

Cards: her art (`LoadoutCards/`, vector PDFs). At most 9 cards, at most 4 per group, at least
one per group present, never more cards than files. Only the groups in the run get a bar
segment, split equally. DCTLs, effects and generators use the clip art; .drfx uses her
bundle card.

Real progress: the file operator reports bytes done (`FileOpProgress`). The story never runs
ahead of that, and never faster than her pace (real installs take a few milliseconds, so
without the cap every card would land at once).

Reduce Motion: no flights, flips or bounces; a 0.3 s crossfade between the open and shut case
while the bar follows real progress.

## Stills

Debug builds render stills offscreen: `open -g -j -n --env LOADOUT_RENDER_CASE=/folder
Loadout.app` writes her demo at fixed times (install and uninstall), stills from a real
sandbox install, a slow copy, Reduce Motion, the toast and the drag-over case, without a
window or focus. There is no film; app demos are recorded by hand.
