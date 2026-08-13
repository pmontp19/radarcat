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

## Tile sources: two different grids, two different zoom levels

`RadarAPI` fetches `{z}/{x}/{y}` PNG tiles from `static-m.meteo.cat`, but radar and base map are
NOT the same pyramid and must not be treated as one:

- **Radar** (`radarTileURL`) only exists at **z=7** (`RadarGrid`: x 63...68, y 78...83; some of
  those indices 404 and are silently skipped - kept for margin, not all are valid). Confirmed
  there is no z=8 radar endpoint (404). Its tile y increases **southward**.
- **Base map** (`fonsTileURL`, `GoogleMapsCompatible`) exists at both z=7 and z=8, and these are
  two *different, unrelated* images, not two levels of the same pyramid:
  - z=7 (the grid this app used to use for the base map too) is a small pre-rendered widget image
    chopped into a 6x6 tile grid, **not a continuous geographic pyramid**. Almost the entire
    labelled Catalonia map (Vielha to Tarragona, Lleida to Girona) lives inside one single tile,
    `x=64, y=80`; a "Tortosa" fragment next to the meteo.cat logo sits disconnected in tile `y=79`
    (leftover branding, not real geography); tile `y=81` has a genuine ~24px solid black border
    baked into its very first row. Net effect: this grid cannot show Terres de l'Ebre at all -
    real content runs to the *literal last pixel row* of tile `y=80` with zero margin before that
    black border. This grid is no longer used for the base map, only kept as historical context.
  - z=8 (`BaseGrid`, what `RadarCompositor` uses now) **is** a real, continuous projection: it
    contains Terres de l'Ebre/Tortosa correctly, continuous with the rest of Catalonia, no black
    border, no disconnected fragment. Its tile y increases **northward** - opposite of both the
    radar grid and the old z=7 base grid. This was discovered and verified by loading Meteocat's
    own `ginys/mapaRadar` widget in a real browser (Chrome DevTools MCP), reading the network log
    for the exact tiles it fetches, and replicating that compositing ourselves pixel-for-pixel
    before touching any code - don't trust a formula for this source, verify by rendering.

Because radar only exists at z=7 and the base map now uses z=8, `RadarCompositor.compositeFrame`
draws each radar tile **scaled 2x** onto the z=8 canvas (standard XYZ nesting: base tile `(X,Y)` is
a child of radar tile `(X/2, Y/2)`) - see the code comment there for the exact anchor math, which
must account for the two grids' opposite y-directions. `catalunyaTileX`/`catalunyaTileY` (in
`BaseGrid`'s coordinate space now, not `RadarGrid`'s) are tuned against pixel measurements of the
debug PNG, not derived from a formula - see the comment above those constants. If Meteocat's tile
set changes, redo this by rendering the real widget and measuring again, not by recomputing from
lat/lon (the tile-index-to-lat/lon relationship for these grids is not standard Web Mercator).

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
