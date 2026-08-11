# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

## What this is

RadarCat is a macOS menu-bar app (SwiftPM, no Xcode project) that composites Meteocat radar
tiles over a base map and crops the result to Catalonia, shown in a `MenuBarExtra` popover with
a 10-frame animation (`RadarAnimator`) built every refresh cycle (`RadarStore`, 6 min).

## Build, run, verify (no Xcode)

- `swift build` - compiles. `swift test` if tests exist.
- `Scripts/compile_and_run.sh` - kills any running instance, builds release, packages, launches,
  and waits for the process to come up. Prefer this for iterating; it needs `APP_NAME` set
  (`BUNDLE_ID`/`MENU_BAR_APP` are read straight from the environment by `package_app.sh`, e.g.
  `APP_NAME=RadarCat BUNDLE_ID=com.pere.radarcat MENU_BAR_APP=1 ./Scripts/compile_and_run.sh`).
- `Scripts/package_app.sh [debug|release]` - lower-level: builds and assembles `<APP_NAME>.app`
  without killing/relaunching. Use this only if you need the `.app` bundle without running it.
- There is no automated visual test. `RadarCompositor.compositeFrame` ends with a debug line,
  `Self.savePNG(out, to: "/Users/pere/Desktop/radarcat_appframe.png")`, that dumps every composited
  frame to disk - opening the popover (or just launching, since `RadarStore.init` refreshes
  immediately) rewrites it. Framing/orientation changes must be verified by reading that PNG as an
  image and, for anything animation-related, by actually watching the popover (it's a distinct
  code path only in the sense that `RadarAnimator` calls `compositeFrame` repeatedly - same
  renderer, so if the debug PNG is right the animation is right, but watch it once to be sure).
  Leave the `savePNG` line in place; it's the only verification hook this project has.

## Tile source: not a normal slippy map

`RadarAPI` fetches `{z}/{x}/{y}` tiles from `static-m.meteo.cat` (radar + `GoogleMapsCompatible`
base map) using standard XYZ convention: **y increases southward** (confirmed empirically -
tile y=78 shows terrain only near its north edge, y=83 is blank sea). But the grid used by this
app (`RadarGrid`: z=7, x 63...68, y 78...83) is **not a continuous geographic pyramid** - it looks
like a small pre-rendered widget image chopped into a 6x6 tile grid, with real irregularities:

- Almost the entire labelled Catalonia map (Vielha to Tarragona, Lleida to Girona) lives inside
  one single tile, `x=64, y=80`. Don't assume neighbouring tile indices are geographically
  adjacent to it - they aren't.
- Tile `y=81` has a genuine ~23px solid black border baked into its top edge (verified on the raw
  tile bytes, not a compositing artifact). Any crop reaching past `y≈80.0` shows that as a stray
  black line.
- Tile `y=79` contains a disconnected fragment - a "Tortosa" label next to the meteo.cat logo over
  open sea - that does not geographically connect to what's south of it in tile `y=80`. It's most
  likely leftover branding/placeholder content for out-of-range tiles, not real northward
  continuation. Treat content there as untrustworthy for framing purposes.

Net effect: Tortosa is not reachable with a label inside this tile grid without either showing the
black border (going south past `y=80.0`) or the disconnected branding fragment (going further
north than the real map, past `y≈79.0`). `RadarCompositor.catalunyaTileX`/`catalunyaTileY` are
tuned by eye against the debug PNG for this reason, not derived from a formula - see the comment
above those constants for the current values and the margins they were chosen for. If Meteocat's
tile set changes, redo this by eye, not by recomputing from lat/lon.

## Coordinate convention in RadarCompositor

`compositeFrame`'s `CGContext` stays in **native Core Graphics coordinates** (origin bottom-left,
y increasing upward) - no CTM flip. `CGContext.draw(image:in:)` places an image relative to its
own bottom-left corner in the *current* transform, so drawing under a y-flipped CTM renders every
tile upside down; that was the cause of a full vertical mirror this project shipped with once.
Keep `catalunyaCrop` and `drawTile`'s `dx`/`dy` math in that same native space rather than
reintroducing a display-style (top-left, y-down) flip.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
