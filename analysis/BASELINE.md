# Initial baseline — 2026-09-13

The installation contains 186 files, totaling 1,401,324,392 bytes. Its readme describes the v3.1 patch; that text alone does not establish the precise executable revision.

## Main executable

- File: `TotalA.exe`, 1,178,624 bytes.
- SHA-256: `3b9c0fadabf3dc67ed5f05a70f1e1505a0c65deadd1a3c930adfe30e2a84995e`.
- PE32, x86 (`0x14c`), image base `0x00400000`.
- Entry point: `0x004e6fa0` (not yet identified as a gameplay function).
- `.text` virtual size: 1,026,346 bytes.
- Imports include DirectDraw, DirectSound, DirectPlay, Win32 windowing/GDI, and Smacker. Audio-related imports also reference the installation's `WIN32.dll`; inspect that DLL before assuming standard Windows multimedia behavior.
- Embedded source paths mention `endgame.cpp`, `frontend.cpp`, `multi.cpp`, and `wargame.cpp`. These are clues, not recovered source files.

## Assets

93 UFO, 13 HPI, 7 CCX, and 1 GP3 archives. All 114 have the same first eight bytes (`4841504900000100`, beginning with `HAPI`). This suggests a common container family; directory decoding and payload decompression have not yet been implemented or verified.

The installation also contains `TAE.EXE`, 18 MP3 files, support libraries, documentation, and other data. See `inventory.json` for exact hashes and filenames and `executables.json` for the import lists.

## Current limits

Static inspection does not establish runtime behavior, archive load order, full function coverage, or a buildable source tree. Subsequent reverse engineering should label hypotheses separately from behavior confirmed in the original game.

## Completed Ghidra pass

Ghidra 12.1.3 imported and analyzed the local executable copy and saved the project successfully. The exporter processed 2,641 identified non-external functions: 2,640 produced pseudocode, and one (`0x004e5392`, 467 bytes of identified function body) failed. These counts are not proof that every original function was discovered or reconstructed correctly.

`local/decompiled/TotalA.decompiled.c` contains 4,630,722 bytes of approximate C. `functions.tsv` records each function and its export status. `string-references.tsv` maps recognized literals to reference sites and containing functions.

Initial navigation anchors, based on literal references rather than confirmed function roles:

| Address | Evidence | Investigation target |
| --- | --- | --- |
| `0x0041d4c0` | `*.HPI` and drive-based HPI wildcard | Archive discovery |
| `0x0041ec50`, `0x0041f7f0` | `endgame.cpp` path | End-of-game handling |
| `0x00425860`, `0x004259b0`, `0x00425a90`, `0x00426e80` | `frontend.cpp` path | Frontend behavior |

The initial import resolved symbols from available Windows libraries but did not resolve the local `SMACKW32.DLL` or `WIN32.DLL` libraries. Their import entries remain visible; their implementation and ordinal names require a separate dependency analysis. No original PDB was found.
