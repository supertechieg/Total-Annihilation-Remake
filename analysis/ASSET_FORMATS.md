# Asset decoding and first Godot viewer

This records the initial asset milestone. The viewer now executes original COB instructions; see [COB_VM.md](COB_VM.md) for the subsequent script-runtime implementation and native comparison. Statements below about static initialization and missing COB execution describe that initial milestone, not the current runtime.

## Confirmed in this installation

All 114 archive directories were read successfully, producing 8,646 file entries (duplicates across archives are retained). The catalog includes 358 TNT maps, 803 3DO models, 1,169 GAF archives, 821 FBI definitions, 841 COB scripts, and 157 BOS source files. Counts describe archive entries, not unique active assets.

The original Arm Commander BOS source is present at `totala1.hpi:scripts/ARMCOM.BOS`. Its `Create()` routine hides `rbigflash`, `lfirept`, and `nanospray`. The static preview reads this initialization to hide the flash geometry. This does not implement a script interpreter, and the base archive source has not been established as equivalent to every patched COB version.

The converter uses explicitly selected sources:

| Asset | Archive and entry |
| --- | --- |
| Terrain | `ccmaps.ccx:maps/Comet Catcher.tnt` |
| Commander geometry | `totala1.hpi:objects3d/armcom.3do` |
| Palette | `totala1.hpi:palettes/PALETTE.PAL` |
| Textures | `totala1.hpi:textures/*.gaf` |
| Commander definition | `rev31.gp3:units/armcom.fbi` |
| Initial visibility reference | `totala1.hpi:scripts/ARMCOM.BOS` |

This is an explicit viewer manifest, **not an inferred implementation of TA archive precedence**. `local/viewer-assets/provenance.json` records each extracted input's origin, size, and SHA-256.

## Implemented

- HAPI directory traversal with case-insensitive lookup, bounds validation, and cycle detection.
- Raw, LZ77, and zlib extraction, outer and inner archive obfuscation, SQSH checksum and length checks.
- TNT tile image assembly using the original 256-color palette; raw elevation bytes exported separately.
- 3DO hierarchy, geometry, texture references, and exclusion of selection primitives.
- GAF first-frame texture conversion, row compression, transparency, and subframe composition support.
- Godot 4.6.2 viewer with pan, zoom, click placement, rotation, recentering, and full-map view.

## Validation

- Eight synthetic regression tests exercise raw/zlib extraction with both obfuscation layers, LZ77 back-references, corrupt checksums, truncation, directory cycles, GAF row decoding, TNT tile placement, and invalid model headers.
- Independently compressed copies of Comet Catcher from `ccmaps.ccx` (zlib) and `Cometctr.ufo` (LZ77) decode identically: 5,377,276 bytes, SHA-256 `c146eadda7e27b7a9f2146cc8e41de22576ab03d4bcb25112f1abc8245cec099`.
- Godot headless startup and control-state checks pass.
- An actual OpenGL render was captured and visually checked. The initial pass exposed visible muzzle-flash geometry and sidebar overflow; both were corrected and recaptured.

## Remaining fidelity work

Only the selected viewer assets have been decoded end to end; directory indexing is not a full corpus extraction test. GAF subframe composition needs validation on real layered sprites. Texture animation, team-color semantics, exact polygon UV orientation, original projection, lighting, and unit scale need comparisons against the game. The commander is in a static model pose. The terrain image omits feature objects, water animation, fog, and other dynamic layers. Heights are exported but not applied to placement or occlusion. General concave-face triangulation is not implemented.

Godot renders the preview; it does not yet implement TA simulation, pathfinding, weapons, economics, COB VM, saves, or multiplayer. Keep those systems independent of presentation. Do not treat generic Godot physics as a faithful substitute for recovered TA behavior.

## Format references consulted

These existing implementation sources were used to understand layouts and compression. RWE has not been linked or adopted as the game engine.

- [HAPI structures](https://github.com/MHeasell/rwe/blob/master/src/rwe/io/hpi/hpi_headers.h)
- [HAPI decoding](https://github.com/MHeasell/rwe/blob/master/src/rwe/io/hpi/hpi_util.cpp)
- [TNT structures](https://github.com/MHeasell/rwe/blob/master/src/rwe/io/tnt/TntArchive.h)
- [3DO structures](https://github.com/MHeasell/rwe/blob/master/src/rwe/io/_3do/_3do.h)
- [GAF structures](https://github.com/MHeasell/rwe/blob/master/src/rwe/io/gaf/gaf_headers.h)
- [GAF decoding](https://github.com/MHeasell/rwe/blob/master/src/rwe/io/gaf/gaf_util.cpp)
- [RWE license](https://github.com/MHeasell/rwe/blob/master/LICENSE)
