# Skirmish maps

The host can now load every official multiplayer map that its feature loader reproduces, not only the bundled Comet Catcher. The viewer has a map picker, and the Commander and opponent start at the map's OTA start positions.

## Recovered original behavior

- **TNT 0x2000 feature loading (`0x483a99..0x483b4e`).**
  1. **Pass 1.** Stores each cell's height byte, and writes the void code `0xfffc` through `0x423c50` for every attribute word equal to `0xfffc`.
  2. **Pass 2.** Unless a saved game is being restored (`game+0x38d6b`), calls `0x423c50(cell, code, null, null, 10)` in row-major order for every attribute word below the map's feature count. Attribute words `0xfffe`, `0xfffd` and `0xfffb`, and out-of-range indices, are ignored.
  3. **Schema features.** `0x423160` then places features listed in the OTA schema.
- **Placement (`0x423c50`).**
  - Code `0xffff` returns. Code `0xfffc` writes the void code at the cell and returns.
  - Footprints past the map edge fail, using signed footprint shorts.
  - Every covered cell that holds a code is removed with `0x4246b0(cell, 0)` in row-major order. A failed removal of a void, reserved or indestructible feature makes the placement fail, but removals already made are kept.
  - Features with an object need a free record from the 0x800-entry instance pool; exhaustion fails after the removals.
  - The anchor code is written even for zero-sized footprints, followed by `0xfffe` continuations with row and column offsets and a cleared instance bit.
- **Removal (`0x4246b0`).** Continuations resolve to their anchor. Codes of `0xfffb` or higher refuse removal, and so do indestructible features unless forced. Removal frees the instance, then clears the anchor and every `0xfffe` cell inside the footprint.
- **Blocking predicate (`0x47de60`).** Empty cells pass. Loaded features pass unless they are flagged blocking. Every other code (void, reserved, out of range) blocks, and continuations use their anchor's code.

## Implementation

- **`map_feature_loader.py`.** The two-pass loader with placement, removal, pool exhaustion and the blocking predicate. `test_map_feature_loader.py` has 8 unit tests.
- **`prepare_maps.py`.**
  - Scans the official archives: `totala1`–`4`, `ccmaps`, `btmaps` and `tactics1`–`8`. `--include-ufo` adds third-party maps. The archive order is a provisional precedence.
  - Keeps maps whose OTA has a schema of Type `Network`.
  - Builds one bundle per map in `local/maps/<slug>/` with the same files as `viewer-assets`: terrain (downscaled above 8192 px), minimap, heights, metal, blocking, `metal.json` placements plus voids, and `scene.json` with the environment and start positions.
  - Writes `local/maps/index.json` (version 2), listing unsupported maps with a reason.
  - `run_viewer.ps1` prepares the bundles when they are missing or stale.
- **Host.** `ConstructionWorld.load_map_features(placements, voids)` writes void codes before placing features, and `FeatureWorld.VOID` is added.
- **Viewer.**
  - `--map <slug>`, or the sidebar map picker (which reloads the scene), selects a bundle.
  - The Commander starts at OTA start position 1, and `start_opponent` uses start position 2.
  - The sidebar shows the map name and size, and the terrain sprite honours `terrain_scale`.

## Coverage

- **Maps.** All **96** official multiplayer maps load.
- **Schema features.** The 9 maps whose OTA schemas list extra features now place them (see `MAP_FEATURE_SPRITES.md`).
- **Oversized maps.** Seven Islands (1280×1280 cells) prepares with a scaled terrain image.
- **Before the loader was traced.** Only 48 maps loaded; 32 were rejected for overlapping placements and 15 for reserved codes. All of them now resolve through the original rules.

## Evidence

Figures below are from the first map checkpoint. With schema features and Seven Islands added, the oracle matches 1,985 of 1,985 checks over all 96 maps, and `test_maps.gd` passes 480 checks (see `MAP_FEATURE_SPRITES.md`).

- **Native loader.** `native_map_features.py` runs the original `0x423c50`/`0x4246b0` in the loader's two-pass order. Model-instance creation, geothermal effects and the pathing refresh are stubbed, and the instance pool is linked as `0x421f20` does.
  - It covers 300 random grids with voids, reserved codes, out-of-range indices, zero or negative footprints, indestructible and object-less features, plus a pool-exhaustion grid.
  - It also covers the actual attribute grids of all 95 official multiplayer TNTs with resolvable features.
  - `compare_native_map_features.py` matches **1,188 of 1,188** grids (26,137,264 cells): codes, continuation offsets and instance bits. This runs in `-Native`.
- **`test_maps.gd`** passes 430 checks: all 86 prepared maps load in about 40 s.
  - Grid sizes match, both start positions reach open ground, and the metal map loads.
  - Every loaded feature is placed.
  - Host blocking (blocking instances plus voids) equals the prepared `features.bin`.
  - The world steps.
- **Real viewer runs.** Commander combat passes on Sherwood (Arm) and The Cold Place (Core) in NORMAL verification, and also passed on Red Hot Lava. A rendered Sherwood capture shows the terrain, the picker and the start position.

## Limits

- **2D features.** GAF sprites are drawn as of `MAP_FEATURE_SPRITES.md`.
- **Not implemented.**
  - Burning and the older TNT attribute layout.
  - Tidal, wind and gravity come from the OTA through the existing environment code; team resources ignore the schema values.
- **Start positions and AI.** Start positions beyond two players are recorded but unused, and the opponent AI is still the scripted base builder.
- **Content.** Archive precedence is provisional; maps whose features fall outside the unit bundle profile would be rejected, and none of the 96 are.
