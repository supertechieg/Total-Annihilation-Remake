# Order and cursor selection, group issue

This checkpoint ports how the original turns a click into orders. It covers:
- the order selector `0x43f0e0` (order mode × unit × hovered unit × cursor position → order type);
- the cursor selector `0x43e490` and the cursor aggregation over the selection `0x48d220`;
- the predicates canRepair `0x4899b0`, canReclaimUnit `0x489960`, canLoad `0x489a90`, the alliance test and the inline featureVisible test;
- the group issue `0x48cf30`: recipients, per-unit type, formation offsets, Shift, hover target;
- the acknowledgement `0x438880` and its reply gate `0x47f780`.

It builds on `order_queue.gd` (`issue()` = `0x43afc0`). Handlers and world integration are not part of it.

## Files

- **`godot/order_selector.gd`.** Static functions over plain Dictionaries whose keys carry the native offsets:
  - game: `local_player_2a42`, `viewing_player_2a43`, `interface_37efa`, `sea_level_1427f`, `hover_2cba`, `cursor_2caa`, `mode_2cc3`, the feature cells `cells_14287`, feature flags, the seen bitmap `seen_14273`, `players`, `units`;
  - player: `index_146`, `seen_w_80`/`seen_h_84`, `alliance_108`, the unit range `units_first_67`/`units_last_6b`;
  - unit: `loco_0`, three weapon records (`flags_111`, `energy_c0`, `metal_c4`), `slot1_3b`, 16.16 `x_6a`/`y_6e`/`z_72`, `transporter_86`, `cargo_8a`, `def_92` (`f241`, `f245`, `footprintx_14a`, `buildlist_156`, `maxy_16e`, `depth_1be`, `minwaterdepth_1c0`, `weapon1_1ee`, `maxdamage_1fa`, `transport_size_22a`, `transport_capacity_22b`), `player_96`, `alive_a6`, `resources_ec`, `select_fb`, `owner_ff`, `build_104`, `health_108`, `f110`.
  - Entry points: `order_type`, `cursor_id`, `aggregate_cursor`, `can_repair`, `can_reclaim_unit`, `can_load`, `feature_visible`, `allied`, `selectable`, `group_issue`, `acknowledge`.
- **`tools/native_order_selector.py`.** The oracle (reuses the table build, allocator and queue hooks of `tools/native_order_queue.py`).
- **`godot/compare_native_order_selector.gd`** and **`godot/test_order_selector.gd`.**

## Recovered rules

Full branch lists are in `ORDER_HANDLERS_RESEARCH.md` "selector" §2–§4; the port follows them line by line. The rules that matter most:

- **Hover gate.** A hovered unit without f110 0x10000000 makes `0x43f0e0` return 0 in every mode. `0x43e490` has no such gate.
- **Alliance.** `byte[u.player+0x108+byte[h.player+0x146]] != 0`. An own unit is an ally only when its own byte is set. Mode 13 (capture) compares player records, not alliance.
- **Mode 1, Left-Click interface.** Enemy → mode 3 (canattack) or mode 12 (canreclamate). A hovered nanoframe the unit can repair → mode 8. An own selectable unit → 0 (the click selects). Then resurrect/reclaim a visible feature, then move.
- **Mode 1, Right-Click interface** (`37efa == 1` only; 2 and 0x101 behave as Left-Click). Reclaim enemies directly, repair/help-build allies, land on allied airbases, pick up loadable units, guard allies.
- **featureVisible.** Seen square `lx = s16(x)>>5`, `lz = (s16(z) - s16(y)>>1)>>5` against the unit's player bitmap size. The word index wraps in 32 bits, and the bit is `1 << (viewer & 31)` on a 16-bit word. Then the cell at `x>>20, z>>20`: a direct occupant must be below the feature count; a 0xfffe back link has no count check. The feature definition byte +0xfe needs 0x80.
- **canRepair.** Needs 0x200. Equal (not "at least") health rejects, as does airborne state 2. Aircraft without amphibious need `y + maxy >= sea` and then pass. Others need `y + maxy >= sea - depth_1be`.
- **canLoad.** Counts only cargo chain members whose +0x86 is the transport. It also needs:
  - a signed footprint word no larger than the size byte;
  - `minwaterdepth < 0` for ground transports;
  - `y + maxy > sea << 16` (strict);
  - build == 0.0.
- **Cursor aggregation `0x48d220(mode)`.**
  - The hovered unit is removed from the selection by moving the last element into its slot.
  - With nothing left: 0xf when the argument is mode 1 and the hover is selectable (no alive test), else 0x13.
  - Otherwise the signed minimum of 0x13 and `0x43e490(G+0x2cc3, s, H, cursor)`: the per-unit mode is the UI mode byte, not the argument.
- **Group issue `0x48cf30(input, mode, type, pos, p5, p6)`.**
  - Shift is input+8 bit 2.
  - The hover is excluded from the recipients and passed as target when a mode other than 5/10/14 is given, or in mode 0 when the type has static 0x200.
  - Recipients are the local player's unit range with f110 0x10, minus the hover.
  - Centre is `trunc(sum(s16 int x) / n) << 16` (and z).
  - Per unit: mode ≠ 0 → `0x43f0e0(mode, s, H, cursor)` (the cursor, not pos), keeping the type argument's high bytes. A zero type is skipped, as is Standing_FireOrder without f245 0x2 and Standing_MoveOrder without 0x1.
  - Formation types (static 0x2) with a pos get `pos + (s - centre)` when `hi32(dx²) + hi32(dz²)` (32-bit sum) is at most `n*3000`, inclusive.
  - Then `0x43afc0(t, shift, s, H, P, p5, p6)`.
- **Float compares.** Every build-fraction test (`fcomp [0.0]; fnstsw ax; test ah, 0x40`) checks C3, which is also set for unordered results, so a NaN build fraction counts as finished (selectable, "repair" rather than "help build", loadable). The D-gun cost test checks C0 (less or unordered), so NaN energy/metal gives cursor 3. `fzero()` in the port mirrors this.
- **Acknowledgement.** `0x438880(order, sound)` clears a pending 0x2000 and calls `0x47f780(unit, 5, sound)`. That replies only for a unit whose owner byte is the viewing player, with f110 0x10000000 set and 0x4000 clear. A null sound uses reply table entry 5 (`0x5086e8 + 5*0x18`); it is null in the image and filled at runtime. The priority queue `0x47fad0` is not ported.

## Corrections to the research spec

- **`0x48d220` per-unit mode.** It uses the UI mode byte `G+0x2cc3`, not its argument (FIXED; the spec said `0x43e490(mode, …)`). The argument only matters for the empty-selection result.
- **Removal order.** `0x480100` swap-removes, which changes the order of `0x43e490` calls and so the range-test calls. The port first used an ordered remove; the oracle caught it.
- **Reply gate.** `0x47f780`'s gate (viewing player, alive, not 0x4000) and the reply index 5 were not in the spec.
- **Type high bytes.** `0x48cf30` passes the whole type dword (high bytes of the argument) to `0x43afc0`. The queue uses only the low byte, so nothing changes. 647 issued orders exercised this.
- **Predicates.** They now run natively; the asm reading in the spec was correct.
- **NaN build fractions** (audit). The spec's "build == 0.0" is really "equal or unordered" (x87 C3). The port originally missed this; it is fixed with `fzero()`.
- **Oracle bugs.** Two fixed during the work:
  - cargo chains were written before the records that clear them;
  - reserved occupant 0xfffa read past the synthetic feature table.

## Evidence

- **Oracle.** `tools/native_order_selector.py` runs the original code for:
  - `0x43f0e0`, `0x43e490`, the three predicates, `0x4815a0`, `0x438760`/`0x4f8a70`;
  - `0x48d220` with its vector helpers;
  - `0x48cf30` with `0x43afc0`/`0x43adc0`/`0x43a0c0`/target link/destroy;
  - `0x438880`, `0x47f780`, `0x4c5740`.
- **Cases.** 16,000 select cases and 3,000 group cases (20,756 operations) in four phases: 12,000 + 2,500 random, then 4,000 + 500 edge-coverage cases added by the audit (below).
  - *12,000 random select cases.* 17 unit class templates with random flag flips. Hover none/own/ally/enemy/random with its own definition, transporter and cargo chains. 2–4 players with random alliance bytes and duplicated indices. Seen-bitmap sizes 0/1/4/8/16/0x80000000 and feature grids with direct, back-linked, reserved and out-of-count occupants. Sea level 0/20/40/128/255, interface 0/1/2/0x101, modes 0–15 and 0xff/0x101/0x203, 819 null positions. For each case: the order type, the cursor with range-stub calls, and the predicates on five unit pairs.
  - *2,500 random group cases.* Operations are group issue, cursor aggregation, acknowledgement passes, selection flips, hover and cursor moves, and direct inserts with idle/protected flags. The native queues of every unit are dumped after each operation.
  - *4,000 edge select cases.* Resurrect/reclaim feature lookups in both interfaces (direct occupants in and out of count, back links to any occupant, reserved cells, flags with and without 0x80), cursors outside the map but inside the seen bitmap, negative cursor heights, null positions in modes 1/2 that never reach `0x4815a0`, own selectable hovers carried with and without carrier 0x40000000, and NaN build/resource/D-gun-cost fields (3,502 NaN fields in total).
  - *500 edge group cases.* Only the carried selectable hover is selected, so `0x48d220` takes its empty-selection path with a transporter; NaN build fractions in the group.
  - *Totals over all phases:* group issue 9,142, cursor aggregation 2,624, acknowledgement passes 2,248 operations; 14,061 issued orders, 3,152 formation offsets, 315 Shift toggles, 4,725 hover targets, 756 replies, 676 type dwords with high bytes, 1,224 null positions; 38 distinct order types from `0x43f0e0` and all 19 cursor ids; formation radius cases built so the offset equals `n*3000` exactly.
- **Branch-edge coverage** (Unicorn code hooks on the unmodified routines, conditional jumps decoded with capstone, recorded in the validation JSON): **799 / 810** conditional edges taken. `0x43e490` 262/264, `0x43f0e0` 395/402, `0x48cf30` 41/42, `0x48d220` 35/36; `0x4899b0` 18/18, `0x489960` 6/6, `0x489a90` 26/26, `0x43e470` 6/6, `0x438880` 2/2, `0x47f780` 8/8. Each of the 11 untaken edges is impossible, with the reason in the JSON:
  - register re-tests of a condition already passed: `0x43ea64`, `0x43edf4`, `0x43f91a`, `0x43faae`, `0x43fee2`;
  - `pos` null tests after `0x4815a0` already dereferenced it: `0x43f592`, `0x43f61d`;
  - `0x43f23e` fall-through (reached only with depth < sea), `0x43f329` taken (a non-air target reaches it only with hoverattack set);
  - `0x48d064` (n > 0 implies a non-empty range), `0x48d3c8` (a non-empty vector has begin != end).
- **Stubs.**
  - range tests `0x49abb0`/`0x49aa80`: per-unit recorded answers; calls recorded;
  - reply queue `0x47fad0`: recorded;
  - operator new/delete: bump allocator with order ids;
  - `0x489800`/`0x48a0f0`: recorded;
  - handlers: never called.
- **Comparator.** `godot/compare_native_order_selector.gd` matches **422,702 / 422,702** checks. They cover:
  - order types (plus an empty native event log for every `0x43f0e0` call), cursor ids and range-call logs;
  - predicate triples and aggregate cursors;
  - per-operation events: `0x43afc0` calls with type dword/shift/target/position/p5/p6, destroy/free/clear-weapon events and replies;
  - every queue field of every unit, and allocation ids.
- **Tests.** `godot/test_order_selector.gd` passes 142 / 142 (including NaN build/energy cases).
- **Mutation checks (first pass).** 12 mutants were run against the comparator, and 12 were caught:
  - amphibious canRepair exception, hover exclusion without mode 5, aggregation using the argument mode, back-link count check, reply ignoring 0x4000;
  - centre floor instead of truncation, Move help-build without ally, selectable without +0xfb, canLoad `>` capacity, ordered removal, viewer bit masked to 15;
  - formation `<` instead of `<=`. This one survived random cases, so boundary cases were added; the rerun gave 1,286 mismatches.
  - All were reverted and the full match re-confirmed.

## Adversarial audit

- **Disassembly re-read.** `order_selector.gd` was compared instruction by instruction with `0x43f0e0` (both jump tables decoded: modes 1–14 → `0x43f9e9, 0x43f845, 0x43f154, 0x43f7e8, 0x43f735, 0x43f701, 0x43f4c7, 0x43f46c, 0x43f3b9, 0x43f82c, 0x43f813, 0x43f4f7, 0x43f6d1, 0x43f7a0`; every `0x438760` name string resolved against `order_table.gd`), `0x43e490` (modes 1–14 → `0x43e505 … 0x43e828`, mode 10 → 0x13), `0x4899b0`, `0x489960`, `0x489a90`, `0x48cf30` (argument order of both `0x43afc0` pushes, `_allmul`/`_allshr` hi32, `ftol(avg*65536.0)`, the byte-wide `0x438760` writes into the argument slots), `0x48d220`/`0x480100`, `0x43e470`, `0x438880` and `0x47f780`. Constants `0x4fd2e8`, `0x4fd748`, `0x4fd758` are 0.0f and `0x4fd760` is 65536.0.
- **Oracle integrity.** Only the documented boundaries are replaced (range tests, reply queue, allocator, `0x489800`/`0x48a0f0`, handler stub); `0x43afc0` is hooked as an observer and runs unmodified. The out byte of `0x43f0e0` is pre-filled with 0x77, so a missing write would show. Gap fixed: the comparator ignored the native event log of `0x43f0e0` calls; it now requires it to be empty.
- **Defect found and fixed (port).** x87 build-fraction compares treat NaN as zero (C3 is set for unordered), but the port used `== 0.0` at eight sites (selectable, canLoad, mode 1 both interfaces, modes 2 and 8, the Left-Click repair cursor). The new NaN edge cases gave 296 comparator mismatches before the fix; `fzero()` fixed all of them. The D-gun cursor was already right, because `not (a >= b)` matches C0.
- **Coverage gaps closed (oracle).** The first edge measurement took 771 of 810 conditional edges. The missing reachable edges were:
  - the Right-Click resurrect/reclaim feature lookups and Left-Click back-link lookups in `0x43e490`, and the Right-Click lookups in `0x43f0e0`;
  - null positions in mode 1;
  - a carried selectable hover in both selectors and in `0x48d220`'s empty-selection path.
  The edge phases cover all of them: 799 / 810, and the other 11 edges are impossible.
- **Mutation-found data gap.** The "seen square y taken unsigned" mutant survived with full branch coverage, because every cursor height was non-negative. Negative heights were added to the edge phase, and the mutant is now caught (201 mismatches).
- **Mutation checks (audit, final trace).** 17 / 17 caught, each reverted byte-exactly (SHA-256 checked):

  | Mutant | Mismatches |
  |---|---|
  | mode table: cursor entry 11 (teleport) moved to 10 | 1,445 |
  | mode table: `0x43e470` hover-kept modes 5/10/14 → 5/11/14 | 5,858 |
  | mode table: order entries 5 and 6 swapped | 5,070 |
  | alliance vs enemy: mode 7 guard uses not-enemy (null hover passes) | 2,374 |
  | alliance byte: only value 1 is allied | 1,861 |
  | canfly bit: canRepair aircraft pass tests canhover | 952 |
  | sea level as signed byte in the mode 3 depth test | 288 |
  | sea level as signed byte in canRepair | 3,182 |
  | featureVisible order: mode 12 reclaim before resurrect | 94 |
  | featureVisible: seen square y taken unsigned | 201 |
  | Shift flag: input bit 3 instead of bit 2 | 21,472 |
  | formation offset: z offset uses the x centre | 11,242 |
  | formation distance: `>> 31` instead of hi32 | 3,219 |
  | predicate equality: canRepair rejects health >= maxdamage | 4,412 |
  | predicate equality: canLoad full at > capacity | 373 |
  | x87 NaN: build compare ordered only | 296 |
  | carried hover selectable when the carrier lacks 0x40000000 | 585 |

  The seen-bit test and the cell lookup inside featureVisible run in a different order in `0x43f0e0` mode 12 (cell first) than at the other sites (seen bit first). Both are pure reads, so the order is not observable except through the null-position crash, which is excluded. The mutant above therefore targets the observable resurrect/reclaim precedence instead.
- **Equivalent forms noted.** The centre division `_idiv` is equivalent to GDScript's truncating integer `/`. The per-iteration re-read of `[player+0x6b]` in `0x48cf30`'s second loop cannot differ, because handlers are never called during the loop.

## Limits

- **Stubs stay stubs.** The range tests `0x49abb0`/`0x49aa80` (immobile attackers' cursor 1 vs 3) and the reply priority queue `0x47fad0` are not ported.
- **Float inputs.** NaN is carried through JSON as the string `"NaN"` and tested; infinities and denormals are not generated (ordinary x87 ordering applies).
- **Out-of-domain inputs.** Natively these read neighbouring memory; the port returns "none"/"not allied" instead. They are not generated: hover ids outside the unit array, player `+0x146` indices of 10 or more, back links pointing before the grid and feature indices past the definition table.
- **Null position.** `0x43f0e0` mode 12 (and mode 1 routed to it) with a null position crashes natively; the port reports an error and returns 0.
- **Inputs are synthetic.** The field meanings marked (I) in the research spec are still inferred: f110 bits 28/29/31, `loco_0` as "mobile", `+0xec`, `+0x156`, `+0x1be`, 0x200 as repair ability, and transport size/capacity. Real FBI-loaded definitions have not been fed through the port.
- **Not wired in.** Nothing in the viewer or worlds calls the selector yet.
- **Not covered.** Mouse dispatch (`0x498f70`, `0x499100`, the dispatcher around `0x499278`), drag-select and the build path `0x419670` are specified in the research file only.

## Viewer integration plan

1. **Adapter.** Build the game Dictionary from the live worlds each input event.
   - Units in id order: player ranges, `f110` from selection/alive/armed/state, and `def_92` bits from the FBI flags the loader sets (`f245`/`f241` tables in the research §0).
   - Health, build fraction and 16.16 positions from `ConstructionWorld`/`CombatWorld`.
   - Sea level from the map, feature cells from `FeatureWorld`, the seen bitmap from `visibility_world.gd`, and alliance bytes from the skirmish setup.
   - `hover_2cba` from `hover_pick.gd` (`0x48cd80`) and `cursor_2caa` from `cursor_projection.gd`.
2. **Order queues.** One `OrderQueue` per unit and one shared id counter. Existing move/attack/ground-attack/reclaim/build/self-destruct code becomes handler bodies (next checkpoint).
3. **Mode buttons** (`0x419be0`), with `G+0x2cc3` held by the viewer:
   - MOVE 2, ATTACK 3, BLAST 4, UNLOAD 5, LOAD 6, DEFEND 7, REPAIR 8, PATROL 9, RECLAIM 12, CAPTURE 13;
   - pressing a button again sets mode 1;
   - STOP sets mode 1 and calls `group_issue(input, 0, Stop, null, 0, 0)`;
   - a build menu entry sets mode 14 with the build type;
   - toggles issue mode-0 orders: Standing_MoveOrder/Standing_FireOrder with p5 0–2, Cloak_On/Off, Activate/Deactivate.
4. **Clicks** (`0x498f70` / `0x499100`):
   - Each mouse move sets hover, then `cursor = aggregate_cursor(g, mode)`.
   - Left click:
     - mode 14 places the build;
     - cursor 0xf selects;
     - cursor ≥ 0x11 does nothing (and in the Right-Click interface in mode 1, deselects);
     - otherwise `group_issue(input, mode, 0, cursor, 0, 0)`.
   - After a left-click issue, Shift keeps the mode; otherwise the mode returns to 1.
   - Right click:
     - outside mode 1 it resets to mode 1;
     - in the Right-Click interface (`interface_37efa` = 1) over the map it issues mode 1 with no cursor check;
     - in the Left-Click interface it deselects.
   - The viewer's current Shift+drag box and A/Ctrl groups stay as they are.
5. **Cursor ids.** Map ids 1–0x13 to the original cursor GAF sequences once they are identified: attack 1, airstrike 2, out of range 3, capture 4, defend 5, repair 6, patrol 7, air load 8, teleport 9, resurrect 0xa, reclaim 0xb, load 0xc, unload 0xd, move 0xe, select 0xf, build 0x10, Right-Click enemy/friend 0x11/0x12, normal 0x13.
6. **Interface option.** Expose Left-Click vs Right-Click (`37efa`) as a setting. Default is Left-Click (0) until the original default is traced.
7. **Acknowledgement.** Call `acknowledge()` from handler bodies at the original sites (the 30 callers of `0x438880`) and play reply index 5 for the returned unit.
