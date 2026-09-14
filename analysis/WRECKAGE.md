# Wreckage features

Destroyed units now leave their original wreck (or heap) as a map feature with the original footprint, blocking, height and resource values.

## Recovered original behavior

- **Feature loader `0x42245x`.** Each definition is 0x100 bytes:

  | Offset | Field |
  |---|---|
  | `+0x94` / `+0x96` | footprint X / Z |
  | `+0xfa` | height (low byte) |
  | `+0x98` | 3D `object` model |
  | `+0xf0` | metal (low 16 bits, as float) |
  | `+0xec` | energy (low 16 bits, as float) |
  | `+0xea` | damage (feature health, short) |
  | `+0xf4` | `featuredead` (resolved after loading) |
  | `+0xfe` | flag word |

  Flag bits: 0 marks a feature without an object (2D sprite, no instance record); 1 animating; 4 flamable; 5 geothermal; 6 blocking; 7 reclaimable; 8 autoreclaimable (default 1); 9 indestructible.
- **Placement `0x423c50(cell, feature, position, angles, owner)`.**
  1. Rejects footprints past the map edge.
  2. Every covered cell that already has a feature must be cleared by `0x4246b0(cell, 0)`, or placement fails.
  3. Features with an object get an instance record from a pool of 0x800 records, each holding position, angles and model.
  4. The anchor cell stores the feature index at `+8` and the instance at `+10`; other footprint cells store `0xfffe` with row (`+10`) and column (`+11`) offsets; the owner nibble goes in `+12`.
  5. Pathing refreshes through `0x440a40`.
- **Removal `0x4246b0(cell, force)`.** Resolves continuations to the anchor. Refuses indestructible features unless forced, frees the instance, and clears the anchor and continuation cells.
- **Corpse selection `0x486360`.** Called after the death explosion for a nonzero corpse type. It starts at the definition's `corpse` (`def+0x1bc`), and each type step above 1 follows `featuredead`. It places at the unit's collision rectangle cell (`unit+0x76/+0x78`) with the unit's position, angles and owner.

## Implementation

- `prepare_units.py` bundles all 1,632 feature definitions with those loader fields, plus 420 converted 3D object models and their textures (`feature_runtime_version=1`; the launcher regenerates older bundles). `prepare_map_metal.py` placements now include feature names; `metal.bin` and `features.bin` are byte-identical.
- `feature_world.gd` holds per-cell codes, continuation offsets and owner nibbles, and implements `place`, `remove`, `place_corpse`, the blocking grid and projectile contact fields. `ConstructionWorld` owns it, loads the map's placements (all 81 Comet Catcher metal features), and rebuilds every cached navigation grid when blocking wrecks change, via the new `TerrainNavigation.rebuild`. `CombatWorld.kill_unit` places corpses after the death explosion and records the anchor.
- **Projectiles.** `WorldCollision.terrain_impact` passes the feature cell code, anchor and heights into the native-compared terrain contact, so shells and beams hit wrecks below their height.
- **Viewer.** Renders wreck models at their instance position.

## Evidence

- `test_wreckage.gd` passes 17 checks:
  - **Grid:** anchor, continuation and offset layout; map-edge rejection; destructible replacement; indestructible blocking and forced removal.
  - **Corpse chain:** type 2 becomes the heap, and type 3 past a heap with no `featuredead` places nothing; feature metal and damage values.
  - **Live death:** a Flash death placing `armflash_dead` at its collision cell, the wreck blocking navigation, projectile impact below and not above the wreck's 20-unit height, and navigation restored after removal.
- `--verify-wreckage` on Comet Catcher (also `--faction core`): the Commander kills an adjacent enemy, and its wreck appears at the correct cell and renders. The whole death, including the navigation rebuild, takes about 0.5 s on the full map. A rendered capture shows the Raider wreck model. All run in NORMAL verification.
- The placement and removal rules come from decompiled code and are not yet executed natively; the underlying terrain contact and feature-blocking predicate are native-compared.

## Limits

- **Resources and damage.** Reclaim (`RECLAIM.md`) and weapon damage with heap replacement (`FEATURE_DAMAGE.md`) are implemented.
- **Water and 2D features.** The underwater sinking branch of `0x486360`, flamable burning, and 2D sprite features are not handled.
- **Pathing refresh.** Rebuilds whole navigation grids rather than the original local refresh.
- **Map features.** Loaded from the prepared placements, not by executing the original TNT loader.
