# First controllable movement slice

Click the terrain to move the Commander. Drag to pan, scroll to zoom, right-click or press S to stop. Orders produce visible routes; the Commander turns and accelerates, plays its original walk script, follows the route and brakes on arrival. Failed orders leave an existing valid order intact.

`mobile_unit.gd` connects the native-verified ground-steering and movement-animation primitives to `terrain_navigation.gd`. The latter is an independently implemented A* grid with a binary heap, octile costs, two-by-two Commander footprint clearance and no diagonal corner cutting. This is a **provisional pathfinder**, not a reconstruction of TA's original path search.

Provisional choices still to replace or verify:

- Terrain passability uses the Commander's FBI slope/depth fields and the height range under its footprint. The original interaction with MovementClass limits remains unresolved.
- Height is sampled from the closest TNT height cell. Pitch currently remains zero, so the verified pitch-dependent speed caps are not yet driven by terrain orientation.
- Route waypoint advancement, arrival tolerance and cell-crossing collision handling are provisional. Other units do not yet block routes; static map-feature blocking is described below.
- Height-to-screen projection remains the existing flat terrain presentation. Sampling world height does not establish native rendering fidelity.
- Heading-to-model presentation is still subject to the renderer coordinate comparison.

The simulation advances at 30 ticks per second and uses original fixed-point steering values. Its script tick precedes the movement tick, matching the observed order in the native unit-update loop. Native movement-state callbacks run after movement. Missing optional MoveRate callbacks are skipped, as the original name lookup permits.

## Validation

Run `tools/verify.ps1 -Native`. Twelve navigation checks cover direct arrival, braking, start/stop callbacks, a wall opening, collision clearance, an unreachable destination, map bounds and diagonal corner cutting. The viewer integration check additionally moves the actual Commander on Comet Catcher from `(3072, 3840)` to within three units of `(3200, 3744)`, waits for rest, and verifies the original script returns to its settled pose without faults.

The movement oracle now also executes original routine `0x0043cd20` for 1,200 seeded waypoint cases, including no-route braking. Its virtual route-provider calls are stubbed to supply three points; original heading, turn clamp, route look-ahead, stopping-distance decisions and velocity code execute. These cases increase the full movement comparison to 6,837 checks. The x87 unit is initialized to an empty stack, masked exceptions and nearest rounding (`FINIT` control word `0x37f`); the process's eventual floating-point configuration still warrants a full-game trace.

Visual capture: Godot `--path godot -- --move --record ABSOLUTE_OUTPUT_DIRECTORY` records 60 deterministic frames of actual movement. Unlike a game session, capture mode advances one simulation tick per rendered frame for reproducibility.

## Next playable systems

Add an expandable original-data bundle for buildable units and structures, separate reusable model instances from the current single-unit viewer, and implement resource accounting and construction orders. Keep the provisional navigation boundary explicit while recovering native terrain/collision semantics. The overall active goal is the entire playable game, including both factions, supported maps, units, weapons, opponents, campaigns and the remaining game systems; this movement slice is an intermediate checkpoint.

## Movement-class terrain fields

The unit bundle now resolves `gamedata/moveinfo.tdf` names and stores normalized movement fields separately from raw FBI data. Original loader analysis shows a resolved class replaces the FBI movement fields; an unresolved class falls back to the FBI. The same content-profile precedence caveat applies to this file as to other imported content. Bundle version `movement_runtime_version=1` makes the launcher rebuild older bundles automatically.

`native_movement_definition.py` executes original initializer 0x4402e0 and loader 0x440340 with supplied integer TDF lookups. All 201 cases match signed 16-bit footprint/depth conversion, byte slope conversion, defaults and slope clamps. Text parsing and the class-name lookup are outside that oracle. Original lookup 0x440420 searches up to 32 class records; the installed selected file contains 15 named classes.

Construction footprints, placement terrain limits, produced-unit navigation and the viewer Commander now use these resolved fields. Navigation also honors minimum water depth, preventing boat routes over dry ground. Eight integration checks cover Commander deep-water access, tank rejection, constructor footprint inheritance, and boat water/land access. This does not implement naval combat, waterline movement, original slope sampling, path costs or the original pathfinder. The A* and footprint sampling remain provisional.

Follow-up: collision occupancy and horizontal collision bounds now consume the same resolved footprints as placement. The selected installed data contains 13 units whose raw FBI footprint differs from the resolved class (including Arm Vader and Core Sumo); the movement integration test checks collision rectangle size, horizontal bounds and placement dimensions for all 13, bringing the test to 48 checks. Building yard overlays and the viewer factory demonstration offset also use resolved dimensions. This closes a host inconsistency; it does not establish naval collision slot or vertical positioning fidelity.

## Separate underwater slope limit

The terrain portion of original movement-cell predicate 0x47de60 rejects low height below sea minus maximum depth, or high height above sea minus minimum depth. It then uses the underwater slope limit when low height is below sea level, otherwise the dry-ground limit. For normalized movement definitions the bad-slope thresholds do not change the Boolean result. `terrain_limits.gd` matches 1,000 original decisions with supplied ordered height bytes, normalized bad slopes, no occupying unit and no feature. Generate/compare via `native_terrain_limits.py` and `compare_native_terrain_limits.gd`; the native verification suite includes both.

Produced-unit and Commander navigation now pass the imported maximum water slope separately. Host checks include a submerged ridge that is traversable with the water slope limit but blocked when exposed (50 movement-class checks total). Current navigation still supplies footprint-wide sampled extrema, not the original prepared per-cell height attributes; feature blocking, exact footprint aggregation and pathfinding remain unfinished. Construction placement retains its existing slope predicate pending its own native comparison.

## Original cell height preparation

`terrain_heights.py` reconstructs the full-map case of original 0x483210: each interior cell receives the minimum and maximum of its four corner height bytes. The rectangle end is clamped to width/height minus one and excluded from iteration, leaving the final row and column unchanged. The helper represents a fresh zero-initialized destination; it does not implement partial terrain deformation updates.

`native_terrain_heights.py` executes the entire original routine across 50 supplied maps and compares all 14,106 cells, including unchanged zero boundaries. All match. This is checked by the native verification suite. It establishes the inputs needed by the previously verified terrain predicate, but is not yet connected to live navigation. Next integration must apply the predicate to each prepared cell before footprint aggregation, and preserve original boundary/feature blocking. Current live footprint-wide extrema can reject a gradual ramp because it compares the total rise across the unit rather than individual cell slopes.

Live integration now prepares each cell's four-corner extrema in `terrain_heights.gd`, applies the verified terrain predicate per cell, then checks the current footprint's covered cells. The Godot preparation itself matches all 14,106 native cell outputs. Navigation tests now include a three-cell-wide unit crossing a gradual ramp and rejecting a sharp local rise (15 checks total). This removes the previous footprint-wide total-rise test. Last row/column quads are blocked explicitly; original additional feature-based map-border restrictions and footprint aggregation still need reconstruction. A* remains provisional.

## Original footprint map aggregation

`native_footprint_passability.py` executes the complete 0x440500 movement-map builder and original cell predicate with allocator/free stubs, no features/occupants, and supplied flat or obstructed terrain. Across 60 maps and footprints from 1 through 6, all 34,560 output cells match a rectangular footprint test plus a one-cell clearance border. Output 0 means blocked; 1 means the footprint fits; 3 means the footprint and its surrounding one-cell rectangle fit. The first comparison exposed the richer value 3 rather than a Boolean 1; the final oracle compares the exact two-bit values.

For this supplied terrain, a map entry is anchored at the footprint's top-left cell and examines width by depth cells extending right/down. This supports the live Boolean all-covered-cells test, but does not yet verify the mapping from moving unit position to the original map query. The original also retains clearance information that the current A* does not use. Dynamic occupancy, feature rules, partial map updates and route costs remain outstanding. No live navigation behavior changes in this research checkpoint.

Live navigation now uses `footprint_passability.gd` for aggregation and retains the original 0/1/3 static terrain clearance values in `terrain_clearance`. A blocked-cell prefix sum computes each rectangle without rescanning every footprint tile. All 34,560 exact values match the original map builder in the Godot comparator. The existing grid-center-to-origin mapping remains unchanged, and A* still treats 1 and 3 as passable without introducing unverified route costs. Building overlays update the separate blocked map; retained clearance describes static terrain only.

## Static map-feature blocking

Original cell predicate 0x47de60 checks features before terrain. Code 0xffff means no feature and passes on to the terrain tests. A direct index below 0xfffb is checked against the loaded feature count: out-of-range indices block, otherwise flag 0x40 in the feature definition's word at +0xfe decides. Code 0xfffe is a continuation cell: the predicate subtracts `row offset (cell +10) * map width + column offset (cell +11)` cells to reach the anchor and uses the anchor's flag; an anchor code above 0xfffa does not block. Codes 0xfffb, 0xfffc and 0xfffd block. The feature loader sets flag 0x40 from the low bit of integer TDF field `blocking`, default 0. The decompiled placement routine writes the anchor index, then 0xfffe with those row/column offsets across `footprintx` by `footprintz`.

`native_feature_blocking.py` executes the original predicate on flat empty terrain. Its 49 original cases cover supplied flag bytes, direct indices, an out-of-range index, reserved codes and a continuation. It additionally evaluates every cell of six supplied 16x16 multi-feature layouts (1,536 cells), written as the decompiled placement loop writes them with unrelated flag bits set, and compares them with `tools/feature_blocking.py`. All 1,585 match. The placement routine, TNT loader, overlap resolution and deletion are not executed.

`prepare_map_metal.py` now also writes `features.bin`, one byte per TNT cell (1 = blocking feature), and records `feature_blocking_version=1`, per-definition blocking flags, blocked-cell count and SHA-256 in `metal.json`. Its existing safeguards remain: ambiguous or missing definitions, invalid indices, boundary crossings and overlaps are rejected. It now also rejects negative footprints and reserved TNT codes 0xfffb..0xfffe, because the loader's handling of those file codes is untraced. The metal grid is byte-identical (SHA-256 `41db12d9…`), and the original Comet metal pass still matches all 184,320 cells.

**Comet Catcher places no blocking features.** Its 81 placements are the nonblocking `moonmetal01..03`. The six `mooncrater` definitions are blocking but are not placed. The prepared Comet grid is therefore all open, and live Comet navigation is unchanged. Blocking behavior is exercised with synthetic host grids.

`terrain_navigation.gd` accepts the grid as an optional final argument and ORs it into each cell's predicate result before footprint aggregation. A unit is therefore blocked when any covered cell holds a blocking feature, and the retained 0/1/3 clearance treats feature cells like blocked terrain. The viewer loads `features.bin` for the Commander and quits with an error if the file is missing or has the wrong size. `construction_world.unit_navigation` passes the same grid to every cached produced-unit navigation. Building yard overlays restore each cache's static snapshot, which already includes features. The launcher regenerates map bundles without `feature_blocking_version=1` or `features.bin`.

Checks: 14 new navigation checks (29 total) cover an empty grid matching no features, a multi-cell feature's continuation cells, neighboring clearance, a three-by-three footprint around one blocking cell, a two-cell-wide unit routing and moving around a feature wall, and a closed wall. Removing the feature term makes seven of them fail. Four new movement-class checks (54 total) confirm that produced-unit caches inherit the grid and keep it through yard overlay refresh and building removal. The viewer `--verify` run confirms that the Commander and a produced-unit cache both carry the real grid. `test_feature_blocking.py` covers the flag's default and low bit, nonblocking placements, multi-cell coverage, a zero-sized footprint's anchor and boundary rejection.

Provisional or unverified: the moving-unit-to-map-cell mapping (unchanged), TNT loader handling of reserved codes, placement overlap resolution, feature destruction/reclaim/deletion updates, projectile collision with features, the predicate's occupying-unit branch (cell +0), and any feature effect on construction placement (placement rules are unchanged). The zero-sized-footprint anchor case follows the decompiled placement write and was not executed natively. A* remains a provisional pathfinder, not TA's original.
