# First controllable movement slice

Click the terrain to move the Commander. Drag to pan, scroll to zoom, right-click or press S to stop. Orders produce visible routes; the Commander turns and accelerates, plays its original walk script, follows the route and brakes on arrival. Failed orders leave an existing valid order intact.

`mobile_unit.gd` connects the native-verified ground-steering and movement-animation primitives to `terrain_navigation.gd`. The latter is an independently implemented A* grid with a binary heap, octile costs, two-by-two Commander footprint clearance and no diagonal corner cutting. This is a **provisional pathfinder**, not a reconstruction of TA's original path search.

Provisional choices still to replace or verify:

- Terrain passability uses the Commander's FBI slope/depth fields and the height range under its footprint. The original interaction with MovementClass limits remains unresolved.
- Height is sampled from the closest TNT height cell. Pitch currently remains zero, so the verified pitch-dependent speed caps are not yet driven by terrain orientation.
- Route waypoint advancement, arrival tolerance and cell-crossing collision handling are provisional. Map features and other units do not yet block routes.
- Height-to-screen projection remains the existing flat terrain presentation. Sampling world height does not establish native rendering fidelity.
- Heading-to-model presentation is still subject to the renderer coordinate comparison.

The simulation advances at 30 ticks per second and uses original fixed-point steering values. Its script tick precedes the movement tick, matching the observed order in the native unit-update loop. Native movement-state callbacks run after movement. Missing optional MoveRate callbacks are skipped, as the original name lookup permits.

## Validation

Run `tools/verify.ps1 -Native`. Twelve navigation checks cover direct arrival, braking, start/stop callbacks, a wall opening, collision clearance, an unreachable destination, map bounds and diagonal corner cutting. The viewer integration check additionally moves the actual Commander on Comet Catcher from `(3072, 3840)` to within three units of `(3200, 3744)`, waits for rest, and verifies the original script returns to its settled pose without faults.

The movement oracle now also executes original routine `0x0043cd20` for 1,200 seeded waypoint cases, including no-route braking. Its virtual route-provider calls are stubbed to supply three points; original heading, turn clamp, route look-ahead, stopping-distance decisions and velocity code execute. These cases increase the full movement comparison to 6,837 checks. The x87 unit is initialized to an empty stack, masked exceptions and nearest rounding (`FINIT` control word `0x37f`); the process's eventual floating-point configuration still warrants a full-game trace.

Visual capture: Godot `--path godot -- --move --record ABSOLUTE_OUTPUT_DIRECTORY` records 60 deterministic frames of actual movement. Unlike a game session, capture mode advances one simulation tick per rendered frame for reproducibility.

## Next playable systems

Add an expandable original-data bundle for buildable units and structures, separate reusable model instances from the current single-unit viewer, and implement resource accounting and construction orders. Keep the provisional navigation boundary explicit while recovering native terrain/collision semantics. The overall active goal is the entire playable game, including both factions, supported maps, units, weapons, opponents, campaigns and the remaining game systems; this movement slice is an intermediate checkpoint.
