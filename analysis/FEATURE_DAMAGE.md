# Feature damage

Explosions now damage wrecks and other destructible map features using the original rules. When a feature's accumulated damage reaches its `damage` value, it is replaced by its `featuredead` (a wreck becomes its heap, and a heap without one disappears).

## Recovered original behavior

- **Splash feature pass (`0x49a120`).**
  - **Cell window.** The routine reads the weapon's area of effect (`weapon+0xd6`) and uses `radius = area >> 1`. It visits the cells from `centre − (radius/16 + 1)` up to but excluding `centre + (radius/16 + 1)` on each axis, clamped to the map, in rows of z and then x. The centre is the explosion's integer position divided by 16, truncating toward zero.
  - **Per cell.** The feature step follows the unit step. Unless the weapon is `unitsonly` (`0x4000`), continuation cells resolve to their anchor through the row and column offsets. Anchor codes of `0xfffb` or higher are skipped.
  - **Distance.** The test uses the current cell's instance flag (`+0xc` bit 0) and word (`+0xa`), not the anchor's. Placement clears that bit on continuation cells.
    - **Instance flag set.** `0x49a850` returns the length from the explosion to the instance position (`+8`).
    - **Instance flag clear** (continuation cells and 2D features). `0x421eb0` builds a point from the current cell and the anchor definition's footprint: `((footprint + 2·cell) << 19)` on each axis, with a height of `0x485070(point) << 16`.
    - **Result.** Both branches take `fsqrt` of the int32 squares and truncate with `ftol`. The signed high word must be below the radius.
  - **Once per feature.** Each anchor is damaged at most once per explosion; a list of up to 64 anchors records the ones already hit.
- **Feature damage (`0x4244b0(cell, x, z, weapon)`).**
  - **Gates.** Damage requires game option bit 8 (`game+0x37f2f`, set unconditionally at `0x430e90`). Indestructible features (`+0xfe` bit 9) are ignored. In a network game (state 3) the call becomes a packet.
  - **Ignition.** A flamable feature (bit 4) without an instance record, hit by a `firestarter` weapon (`weapon+0x10b`), is ignited through `0x4233a0` instead of damaged.
  - **Features with an instance record.** Features with flag bit 0 are ignored, and the instance's cell coordinates must match. Instance `+0x26` accumulates the weapon's `default` damage (`weapon+0xd4`) as a word. Reaching the definition's damage (`+0xea`, unsigned) calls `0x423550(x, z, 0)`.
  - **2D features.** The anchor cell word accumulates `default + stored`. Reaching the damage calls `0x423550(x, z, 0)`; otherwise the word stores the sum.
- **Replacement (`0x423550` → `0x423710`).** Parameter 0 selects `featuredead`, or `featurereclamate` when the instance has flag 2. The routine removes the feature and places the successor with owner 10:
  - features with an instance record keep their instance position and angles;
  - 2D features use the default position.
  - Placement resets instance damage to 0.
  - 2D features that have animation sequences (`+0xbc`–`+0xc8`) take an animated path instead, which is not implemented.
- **Terrain height (`0x485070`).** Bilinear interpolation over the cell height bytes (`+4`) using the 4-bit fractional position, with truncating divisions by 16. It returns -1 outside the interior cells. Default feature instances use this height (`0x423e3d`).

## Implementation

- **`feature_damage.gd`.**
  - `height` implements `0x485070`.
  - `splash(grid, weapon, position, game_flags)` implements the `0x49a120` feature pass and `damage` implements `0x4244b0`.
  - Both use a grid interface; `ArrayGrid` mirrors raw cells for the native comparison.
- **`FeatureWorld`.**
  - Implements the grid interface. Features with an object use the anchor cell as their instance index. 2D features keep their damage word in the instance record.
  - Stores per-definition damage flags.
  - Default instance positions use the terrain height.
  - `replace` places successors of 2D features at the default position.
- **`CombatWorld.blast`.** After unit splash damage, it runs the feature pass with `GAME_FLAGS = 0xc`. It then applies replacements, counts `feature_destructions`, records ignitions and refreshes blocking. Projectiles and death explosions carry `firestarter` and collision flags.
- **Navigation refresh.** `ConstructionWorld.refresh_feature_blocking` skips navigation rebuilds when the blocking grid is unchanged, as with smudges replaced by smudges.
- **Viewer.** Feature sprites are rebuilt when a replacement keeps the same anchor.

## Evidence

- **Native.** `native_feature_damage.py` covers 1,000 height samples and 1,500 splash cases on a 12×12 map. The cases use random footprints, flags, damage values, accumulators, instances (including mismatched coordinates), weapons and positions, and include 325 cases with hits, 168 replacements and 4 ignitions.
  - The original splash routine runs unmodified to the end of its cell loop, with `0x4244b0` native and `0x423550`/`0x4233a0` recorded.
  - `compare_native_feature_damage.gd` matches 8,668 of 8,668 checks: heights, hit calls in order, replacements, ignitions, final cell words and instance damage. This runs in `-Native`.
- **`test_feature_damage.gd`** passes 13 checks:
  - **Accumulation and gates.** Damage accumulates; `unitsonly` and out-of-radius explosions are ignored.
  - **Replacement.** The wreck becomes a heap at the same position with owner 10 and zero damage. Navigation is freed, and the heap is then destroyed.
  - **Other features.** Indestructible metal features are unaffected, and the zero-damage smudge replaces itself.
  - **Death blasts and heights.** An `armflash` death explosion damages an adjacent wreck by 50, and the default instance height matches the terrain sample.
- **`--verify-feature-damage`** on Comet Catcher runs for both factions in NORMAL verification. The Commander's laser leaves a wreck, then its D-gun, fired at an enemy behind the wreck, blasts through it: `corraid_dead` (damage 846) becomes `corraid_heap`, and `armflash_dead` (500) becomes `armflash_heap`. The sprites follow.

## Limits

- **Not implemented.**
  - Burning: ignitions are recorded but have no effect.
  - The animated 2D replacement path and feature explosions.
  - Network packets.
- **2D feature instances.** 2D features still hold host instance records, although the original has none; the damage rules follow the original.
- **Deduplication.** Replacements are applied after the whole feature pass. This matches the original because each successor shares its anchor, which is already in the hit list, unless a single explosion damages more than 64 features.
