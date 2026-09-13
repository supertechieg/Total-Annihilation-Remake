# Endpoint unit collision

The projectile update reaches `0x49bd86` after position integration and calls `0x49b090`. Its map lookup `0x4815a0` shifts raw X/Z right20 (16 world units per cell), rejects coordinates outside map dimensions, and selects a 13-byte cell. An off-map projectile is marked expired by bit2 at projectile+0x69. The ordinary unit checks here are endpoint tests, not swept segment/sphere intersections.

The cell's first two unsigned16 values are unit indices into the array at game+0x14357 with stride0x118. A unit whose owner byte at +0xff equals projectile+0x66 is skipped. The first slot hits when projectile Y is strictly below unit Y plus definition upper Y; it does not test the lower bound. The second slot hits when Y lies inclusively between translated lower and upper bounds. The first qualifying slot wins. Slot population and their physical interpretation still require tracing; do not assume these correspond to arbitrary nearest units or general alliance relationships.

`projectile_collision.gd` implements cell addressing and unit-slot selection. `native_projectile_collision.py` runs original lookup and collision routines for 600 supplied cases, retaining the actual map lookup. Only impact dispatch is replaced by a target-pointer capture. Weapon flag0x4000 skips the subsequent terrain/feature path; projectile proximity targets are absent. All cell indices, hit targets and expiration states match. Six normal checks include captured height/owner boundaries and off-map addressing. See `native-projectile-collision-validation.json`.

This is not a complete collision implementation. Grid population, terrain/features, water, special projectile proximity and any other projectile-specific paths remain to recover. The viewer still uses provisional swept spheres. Replacing them requires connecting correct cell occupants and original target aiming; retaining spheres temporarily is not a fidelity claim.

## Ordinary unit insertion and removal

`0x47cc30` inserts a supplied unit rectangle at unit+0x76 (cell X/Z) with dimensions at +0x7e. It rejects rectangles whose exclusive end reaches or exceeds either map dimension. For ordinary units, low two bits of unit+0x110 choose the first slot (1) or second slot (2). Buildings with bit0x20000000 follow a separate yard-map path, not implemented here.

Empty slots receive the inserting unit ID. Occupied slots normally retain their occupant and set bit0x4000000 on the incumbent, 0x8000000 on the entrant. If the incumbent's controller at +0x96 has a nonzero first field and byte+0x73 equals3, the entrant replaces it and those flags are reversed. These controller fields are not yet assigned a gameplay name. Removal `0x47d0e0` clears only matching IDs, then clears both overlap bits on the removed unit. It does not automatically restore displaced occupants; downstream callbacks are separate.

`collision_grid.gd` reconstructs these ordinary-slot operations. All300 native insert/remove scenarios match across every cell and all three units' flags, including both slots, overlaps, replacement and rejected edge rectangles. The original routines run with coarse-list linking suppressed; downstream overlap notifications and visibility refresh are stubbed. Eight normal checks cover insertion, flags, removal ownership and boundary rejection. See `native-collision-grid-validation.json`.

World integration still requires rectangle derivation from position, slot classification, building yard maps, movement ordering and overlap notification behavior. This helper is not yet used by playable combat.

## Building yard maps

The same insertion routine uses unit flag0x20000000 to select the yard-map path. This always writes slot0, regardless of the low slot bits. Each row-major yard byte selects occupancy with bit4 when unit+0x10f bit4 is clear, or bit2 when that unit flag is set. Yard bit1 independently sets cell+12 bit2, even on cells that do not receive the unit ID. Existing occupant replacement and overlap flags follow the ordinary-slot rules. Removal clears matching IDs and clears that cell flag wherever the yard byte has bit1.

The helper now accepts supplied decoded yard bytes and the yard-state flag. Native comparison has expanded to600 insert/remove cases, including300 building cases with both yard states, all ten decoded yard values, varied initial cell flags and overlapping occupants. All cell slots, cell flags and unit overlap flags match. Additional map refresh calls `0x483210` and `0x440a40` are stubbed along with the previously documented callbacks. Sixteen normal checks cover ordinary and building behavior. This verifies consumption of decoded yard bytes; text decoding and world yard-state updates still need integration.

## Position to rectangle

Creation copies the definition's footprint dimensions into unit+0x7e. For each horizontal axis, the grid origin is `signed32(position_raw - footprint*524288 + 524288) >> 20`. The footprint dimensions remain the rectangle size. The eight-world-unit adjustment matters at cell boundaries; simply flooring the position and subtracting half the footprint gives different results for even-sized units.

`CollisionGrid.unit_rect` matches600 executions of original creation instructions `0x485ba0` through `0x485bd6`, including120 positions on or one raw unit either side of adjusted boundaries, varied footprints1..8, and signed32 position extremes. See `native-collision-rect-validation.json`. Four boundary checks increase the normal grid suite to20.

Inspection of movement function `0x48a9f0` finds the same formula. It compares the new rectangle origin and requested low-two-bit slot with the existing values. If both match, it updates XYZ only; otherwise it removes the old occupancy, updates position/origin/slot, inserts the new occupancy and refreshes spatial state. It then sets unit flag0x10000. This movement lifecycle is inspected, not yet dynamically compared or connected to the world.

## Verified movement lifecycle

`CollisionGrid.move_unit` now implements that lifecycle. The native grid oracle executes full `0x48a9f0` between insertion and removal for all600 cases. It covers within-cell updates, rectangle crossings, slot changes, transitions outside and back into valid map bounds, and yard-map cases. Comparison checks all cells, terrain flags, all supplied unit flags, the stored position and rectangle origin at each stage. All600 scenarios match; normal grid checks now total24. The spatial refresh `0x4827b0` is stubbed in addition to the previously listed side effects. No collision-avoidance or displaced-unit recovery behavior is inferred from those stubs.

The helper remains separate from the playable world's lifecycle. Its unit records explicitly carry the previous rectangle, slot, insertion state, optional yard bytes and yard state. Integration must preserve this state rather than reconstructing the entire occupancy grid each tick, since doing so would change overlap ordering and within-cell movement behavior.

## Live world integration

`world_collision.gd` now maintains persistent collision records for the playable ground units. ConstructionWorld inserts new units after script creation, synchronizes positions and yard state after script/mobile updates, and removes occupancy before deleting units. This also captures the Commander's externally supplied position on the next world step. Yard-state changes remove and reinsert the building. Seven integration checks cover initial footprint occupancy, movement/old-cell cleanup, factory opening/closing, and deletion. The full normal suite and real-map factory/builder/combat demos pass with this lifecycle active.

The adapter currently assigns ground units to slot0 and does not register aircraft. Flight/submersion classification remains absent. All controllers are conservatively marked non-replaceable until the native controller condition is mapped to world states; overlap callbacks remain unimplemented. Yard codes use the definition-loader mapping, whitespace is stripped, short maps repeat their final character, and missing maps fall back to occupied cells. The malformed/missing-map policy is provisional. Ground height still comes from existing terrain sampling. Original model blast bounds are cached per record.

This live occupancy is not yet consulted by projectile damage or navigation. Those consumers retain their documented provisional behavior until targeting and collision integration are verified. The next step is to consume these records in the projectile path without claiming missing air/naval or overlap behavior is complete.
