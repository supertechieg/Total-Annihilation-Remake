# Map feature sprites and schema features

The viewer now draws 2D map features — trees, shrubs, rocks, vents and plants — from their original GAF sprites, with shadows and animation. The map loader also places the features that a map's OTA schema lists, so all 96 official multiplayer maps load.

## Recovered original behavior

Everything here was found by a reverse-engineering workflow: one analyst per topic plus an independent adversarial verifier who re-read the cited instructions. Where the two disagreed, the verifier's corrections are used.

### Schema features (`0x436c30` → `0x423160`)

- **Schema choice (`0x436860`, modes 2/3).** Schema types Network 1–4 are tried in order. For each type, `Schema 0, 1, …` are walked until an index is missing. A schema matching the type (31 characters, case-insensitive) with S `StartPos` specials is taken when `S ≠ 0` and (`S = P`, or `P = 0`, or `S > best` with `best ≠ P`). `best` starts at 0 once and carries across types, and a later pick replaces an earlier one. `P` is the highest occupied player slot plus one.
- **Source list.** `0x436c30` fills the descriptor list (`+0xdbc`, count `+0xdc0`) with 0x88-byte records.
  - Records follow the child order of the selected schema's `[features]` section; the child section names are not used.
  - `Featurename` is copied with `strncpy` of 0x80 bytes and a forced terminator.
  - `XPos` and `ZPos` are read with MSVC `atol` and default to -1. A negative coordinate blanks the name.
- **Placement (`0x423160`).** It runs after TNT attribute pass 2, from `0x483b4e`; the loader skips both when restoring a saved game, and it only runs for the 4-byte attribute layout. Records with an empty name are skipped. For each remaining record:
  1. **Lookup.** The name is matched case-insensitively (`_stricmp`) against the loaded definitions. An unknown name is loaded by `0x4224b0`, which appends a definition and returns the old count; a missing record is a fatal message box.
  2. **Anchor.** 2D features (flag bit 0) anchor at `(XPos, ZPos)`. 3D features anchor at `(XPos − fx/2, ZPos − fz/2)`, dividing the signed shorts with truncation.
  3. **Cell.** `0x481550` yields a null cell outside the map, and `0x423c50(cell, code, null, null, 10)` receives it without any check. The result is undefined (it usually faults).
  4. **Metal pass.** The feature metal pass `0x422040` runs afterwards, at `0x483d7d`.

### 2D sprites (`0x4224b0` definition load, `0x424050` tick, `0x46a610` draw)

- **Definition load.**
  - A definition without an `object` key sets flag bit 0 and loads `anims/<filename>.gaf`.
  - Eight sequence pointers are resolved at `+0xac..+0xc8`: seqname, shadow, burn, burn shadow, die, die shadow, reclamate and reclamate shadow.
  - Shared per-type animation states at `+0xcc` (main) and `+0xd8` (shadow) start at frame 0 and are armed only for `animating=1`.
- **Animation step (`0x4b8b90`).** `0x424050` steps each animating type once per simulation tick:
  - a counter of 2 or more decrements;
  - otherwise the index advances, wrapping when the GAF entry's loop byte (`+2`) is set and otherwise stopping with the index at the frame count;
  - after advancing, the counter reloads from the low word of the frame table entry's second dword.

  All instances of a type animate in lockstep.
- **Draw (`0x46a610`).** Called row-major for anchor cells.
  - **Screen anchor.** `sx = sar1(cdq(fx<<4)) + col*16 + 128 − viewX` and `sy = sar1(cdq(fz<<4)) − (H00+H10+H01+H11 >> 3) + row*16 + 32 − viewY`. In words: the footprint centre, lifted by the anchor cell's four corner heights summed and shifted right by 3.
  - **Blitting.** Each frame is blitted with its top-left at `anchor − (x, y)`, using the frame header's signed words.
  - **Shadow.** The shadow frame draws immediately before the main frame when the shadow option is on.
  - **Translucency.** `animtrans`/`shadtrans` select the translucent blitter.
  - **Passes.** Features lower than 10 draw in a pass before units; taller ones draw after each row's ground units.

## Implementation

- **Map loader.**
  - `map_feature_loader.py` adds `msvc_atoi`, `schema_features` and `place_schema_features`. `load(...)` takes the schema entries and the extra definitions available by name. Appended definitions extend `grid.definitions`, and out-of-map anchors are skipped and recorded.
  - `prepare_maps.select_schema` ports `0x436860` with `P = 2`, the port's two-player skirmish. It chooses both the start positions and the features; of the official maps only Painted Desert changes, to Schema 1 with no schema features.
  - `prepare_maps.py` places schema features, and `metal.json` records `schema_features` and `skipped_schema_features`. All 96 official multiplayer maps now prepare.
  - `prepare_viewer.tnt_image` takes a power-of-two scale and pastes nearest-sampled tiles. Seven Islands (1280×1280 cells, 20,480 px) builds at 5,120 px without holding the full image.
- **Sprite bundle.** `prepare_units.py` extracts every 2D feature's GAF sequences (`feature_runtime_version=5`).
  - Sequences: all frames of `seqname` and of `seqnameshad`.
  - Per frame and sequence: the frame PNG, its hotspot `x`/`y`, the sequence loop byte and the per-frame durations.
  - Runtime flags: `animating`, `animtrans` and `shadtrans`.
  - Coverage: 1,212 features, 1,884 frames. Seven definitions name GAF sequences that do not exist, mostly shadows; the original lookup finds nothing for them either.
- **Godot.**
  - `feature_animation.gd`: `start`/`step` (`0x4b8b90`) and `anchor` (`0x46a610`).
  - `unit_catalog.gd`: `feature_sprites` and a cached `feature_texture`.
  - `viewer.gd`: `feature_sprite_2d` draws the shadow, then the main sprite, at the recovered anchor and hotspot.
    - Features in the last map column or row are skipped, as the draw loop's range does.
    - Nodes go into a low or tall layer and are kept in row-major anchor order.
    - Animating types get separate shared states for the main (`+0xcc`) and shadow (`+0xd8`) sequences. They are created at map load by `prime_feature_animations` and advanced once per simulation tick.
    - An ended non-looping sequence hides its sprites, since it yields no frame.
    - Replacements rebuild the node.

## Evidence

- **Native oracle.** `native_map_features.py` runs the original `0x423c50`/`0x4246b0` passes, then the unmodified `0x423160` over the descriptor list. `0x4224b0` is replaced by an appending recorder; null-cell placements are recorded and skipped.
  - **Random grids.** 300 grids have random schema entries: mixed-case names, unknown names that append definitions, negative, blank and out-of-map coordinates, and odd or negative footprints.
  - **Real maps.** All 96 official multiplayer maps are included, with their real schemas; Seven Islands is included now that the grid region is 32 MB.
  - **Result.** `compare_native_map_features.py` matches **1,985 / 1,985** checks: final codes, continuation offsets, instance bits, appended definitions and null-cell skips, over 27.8M cells and 1,869 schema entries. This runs in `-Native`.
  - **What the oracle does not cover.** Most of the schema entries are synthetic, and 9 maps supply the real ones. Entries are parsed and the schema is chosen by the Python code (`schema_features`, `select_schema`) before `0x423160` runs natively, so parsing and selection are covered by unit tests, not by the oracle.
- **Unit tests.**
  - `test_map_feature_loader.py`: 11 tests, including `atoi` parsing, 3D centring, appended definitions, skipped anchors and schema selection (the Painted Desert shape at `P = 2`, 3 and 0, and `best` carrying across types).
  - `test_feature_animation.gd`: 10 checks covering the countdown, loop and stop semantics, and anchor rounding and height lift.
- **`test_maps.gd`.** All 96 prepared maps pass, 480 checks.
- **`--verify-map-features`.** Every drawable 2D feature with sprite data has a node exactly at the anchor. The check computes the anchor independently from the raw height grid, and requires features in the last row or column to be absent.
  - Sherwood: 609 sprites. East Indeez: 8,721. Metal Isles: 4.
  - Acid Pools (Core), run with `--require-animation`: 104 sprites and 6 main or shadow animation states, and 68 sprites change their drawn texture over 90 ticks.
  - Sherwood and Acid Pools run in NORMAL verification. A rendered Sherwood capture shows trees, dead trees, rocks, metal rocks, shrubs and shadows.

## Limits

- **Draw passes.** Approximated with z-order: features below height 10 under units, taller ones above.
- **Translucency.** Drawn at half alpha, although the original's translucent blitter uses a blend table and draws nothing when translucency is unsupported.
- **Units and 3D wrecks.** They are not yet lifted by terrain height. On slopes, sprites and units can appear offset relative to each other.
- **Not implemented.**
  - Burning (`seqnameburn`, spread timers, `featureburnt`), die and reclaim animations, and feature reproduction (`reproduce` / `reproducearea` in `0x424050`).
  - Shadow-option and translucency-support toggles.
- **Schema selection.** Fixed at `P = 2`, since maps are prepared once for two-player skirmishes. Other player counts would need per-count bundles. Out-of-map schema anchors, undefined in the original, are skipped.
- **Animation start.** Shared states for types that first appear mid-game, such as a 2D successor feature, start at frame 0 when first drawn.
