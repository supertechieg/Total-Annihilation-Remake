# Line of sight: stamping, lifecycle and visibility queries

This checkpoint follows [LOS_FOUNDATION.md](LOS_FOUNDATION.md). It ports the per-player LOS count grid, the mapped-cell bit grid, temporary LOS and the visibility queries that targeting, drawing and the AI use. Each part had an implementation agent and then an independent adversarial audit with mutation testing.

## Stamping and lifecycle (`godot/visibility_world.gd`)

| Routine | Port |
|---|---|
| `0x482ac0` unit creation | `create_unit` |
| `0x4827b0` → `0x4825b0` position/flags update | `update_unit` |
| `0x482270` / `0x481d50` circular and true LOS count stamps (±1) | `_stamp_count` |
| `0x481930` mapped-bit stamp | `_stamp_map` |
| death path `0x486706` / `0x48672a` → `0x482910` temp LOS, `0x486832` → `0x482090` removal | `kill_unit` |
| `0x482910` / `0x482130` temporary LOS add and expiry (20 slots, compaction) | `add_temp_los`, `expire_temp_los` |
| `0x4816a0` rebuild (optionally resetting mapping) | `rebuild` |

Units are plain dictionaries: `owner`, `pos16`, `sight`, `eye_bonus`, `unit_flags`, `los_col`, `los_row` and `los_slot`, which mirror unit +0x7a/+0x7c/+0xf8.

Native quirks the port reproduces:
- **Temp origin.** `0x482910` never writes a temp entry's origin (+0x20). Compaction copies whole entries and leaves the tail slots alone, so a new entry can carry a stale origin. The port keeps a 20-slot backing store for this.
- **Unchecked death removal.** `0x482090` decrements without checking the slot. A true-mode unit that never registered still decrements, so a cell underflows to 0xFF.
- **Crash on a switch.** After a true→circular LOSType switch, removing a temp entry or unit whose slot is ≥ 10 reads a NULL vismask frame. The original crashes at eip `0x481fd1`; the port reports `fault`.
- **Clipping and indexing.** Circular stamps clip against the map half size but index with the record width (+0x80). Ray cells are `s16(centre + offset)`. The origin is stored and the local redraw bit set before the bounds test.
- **Rebuild with LOS off.** Units are skipped before their slot is reset, so slots are kept.

**Evidence.**
- `tools/native_los_stamp.py` (oracle O3) runs the original routines unpatched. It builds the ray tables with the original loader and uses native `0x4b7f30` frame lookup. It stubs only the height-grid allocator (`0x4b4f10` / `0x4b4f20`) and the two minimap calls at the end of the rebuild (`0x466c20` / `0x466dc0`, call-counted).
- It runs 600 fuzzed sequences, 31,581 steps (83 native faults, all reproduced). Ops: move, create, tick, rebuild, flags, death and temp, including a family that fills the 20-slot cap.
- `godot/compare_native_los_stamp.gd` matches **63,680 / 63,680** checks. Per step it compares hashes of every player grid, the mapped buffer and all temp slots, the unit fields, the temp count, the flags, the redraw bit and minimap call counts, plus fault parity.
- The audit fixed a probe that falsely reported coverage of the temp cap and added about 50 probes that only observe. 19 of 21 mutants were caught; the two survivors behave identically to the original.

## Visibility queries (`godot/visibility_queries.gd`)

- **`0x465ac0` `visible(rec, world, unit)`.**
  - An own unit is visible. Cloaked units and the sea test on P0.y (signed, no +1) exit early.
  - Otherwise it probes four corners of the unit bounds in order: P0 (minX, maxY, minZ), P1 (maxX, maxY, minZ), P2 (maxX, minY, maxZ), P3 (minX, minY, maxZ).
  - With LOS on it reads the LOS count grid; otherwise it reads the local player's mapped bit through `0x408090`.
- **`0x408090` `mapped_probe`.** It is a routine in its own right, stdcall(rec, P16*), that reads the mapped grid only. Its other callers `0x407fbd` and `0x49bf2f` are not yet identified.
- **`0x4658e0` `feature_visible`.** Row math is `s16(row<<4) - (s16(h)>>1)` in 32-bit arithmetic, not wrapped. Feature column B is a 16-bit wrapping sum. The research plan's wrapped row formula mismatches on grids over 1,024 rows.
- **Mapped bit.** The shift is `local_player & 31`, like x86 `shl`.

**Evidence.**
- `tools/native_visibility_query.py` (oracle O5) runs all three routines with no stubs, random register contents and stack-cleanup assertions.
- It makes 114,000 calls in 456 scenes over 19 modes: LOS on/off, local and non-local, mapping off, cloaked, below sea, map edges, tall grids and 16-bit feature wrap.
- `godot/compare_native_visibility_query.gd` matches **114,000 / 114,000**.
- The audit's code-hook coverage reached all 474 instructions and every exit. 23 of 25 mutants were caught; the one real gap (a non-wrapping feature column) was closed with the `feature_wrap16` mode.

## Limits and unknowns

- **Not yet wired in.** Nothing is hooked into ConstructionWorld, CombatWorld or the viewer. That is C5 (world hook), followed by C7 radar, jamming and cloak, C8 targeting gates and C9 fog rendering.
- **Unknown heap contents.** The bytes before the ray-table vector (read for sight < 32 in true mode) and a fresh temp array are zeroed on both sides; the shipped heap contents are unknown.
- **Unidentified sites:**
  - where player record +0x80/+0x84/+0x88 are initialised;
  - where unit +0xa6 is cleared on death;
  - the set-position trigger `0x48a9f0` and the other `0x4827b0` callers.
- **Minimap redraw bit.** The effect of `0x466c20` on redraw bit 0x142f1 is left to the minimap renderer.
- **Bounds loader.** `definition_bounds` follows the definition loader at `0x42d079..0x42d107` from the disassembly but was not run natively.
