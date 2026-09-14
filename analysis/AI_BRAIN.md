# Computer player: brain plumbing and group assignment (AI CP1 + CP7)

First two checkpoints of the skirmish AI port plan (`analysis/SKIRMISH_AI_RESEARCH.md` §1.3, §1.4, §2.1, §2.3, §2.4). This checkpoint adds the brain object, its tick cadence and the 30-tick group assignment. The think bodies (build chooser, placement, attack forces, aircraft) are stubs; they are later checkpoints.

Every fact below marked **native** was read from the disassembly of `local/original/TotalA.exe` and, where stated, executed by the Unicorn oracle. Nothing here claims parity for the think bodies, the weapon scheduler or the knowledge refresh.

## Shared RNG (`0x4b6c30`, state `0x51fc88`)

- `cmp edi, 2; jge` is a **signed** test: `n < 2` returns 0 and does not touch the state.
- Otherwise the Park–Miller step (multiply-high form of `state·16807 mod 0x7fffffff`, a non-positive result gets `+0x7fffffff`) is stored, then `state % n` with **unsigned** `div`.
- **Reuse, no new module.** `godot/wind_state.gd` `bounded_random(n)` / `game_seed` is already exactly this routine (checked against the native step over 200k seeds in `test_cob_rand.gd`; seed 0 degenerates to `0x7fffffff` in both). `ConstructionWorld.game_random` is the shared stream used by COB `RAND`, firing spread and self-destruct. `ai_brain.gd` takes that object; `godot/ai_random.gd` was therefore not created.

## Brain construction (`0x408cb0`, called from `0x464700` at `0x4648b8`)

- **Who gets one (native, `0x46489d`).** A 0x3d-byte brain is built when the record word `[player] == 0` **or** `type (+0x73) != 3`. It is stored at `player+0x74`, then the AI context `0x40b320(side)` is created.
- **Fields.** `+0` player record, `+4` side byte (`player+0x146`), `+5` countdown = 30, `+9` = 0 (use unknown), `+0xd` commander build block = 0, `+0x39` weapon cursor = 0, `+0x11..+0x35` ten handler pointers (slot 0 zeroed by `rep stosd`, never filled).
- **Handler objects.** `+0` vtable, `+4` brain, `+8` group object `[player+0x78] + k·0x20`, `+0xc` wake = 0, `+0x10` side (dword of the side byte). Code allocation order is slots 1, 4, 5, 2, 3, 6, 7, 8, 9; this only affects heap addresses, not behaviour. No RNG is drawn during construction.

| slot k | vtable | think | size | wake set by prologue | stored params |
|---|---|---|---|---|---|
| 1 | 0x4fc9b0 | 0x4086d0 | 0x14 | tick+30 | – |
| 2 | 0x4fc988 | 0x4077e0 | 0x28 | tick+300 | +0x14=3, +0x18=6, +0x1c=20000, +0x20=3, +0x24=0 |
| 3 | 0x4fc990 | 0x4079f0 | 0x18 | tick+150 | +0x14=2 (slot of the force it feeds) |
| 4 | 0x4fc9a8 | 0x408100 | 0x14 | tick+90 | – |
| 5 | 0x4fc980 | 0x407380 (`ret`) | 0x14 | never | – (base class) |
| 6 | 0x4fc988 | 0x4077e0 | 0x28 | tick+300 | +0x14=3, +0x18=6, +0x1c=50000, +0x20=7, +0x24=0 |
| 7 | 0x4fc990 | 0x4079f0 | 0x18 | tick+150 | +0x14=6 |
| 8 | 0x4fc998 | 0x407ae0 | 0x14 | tick+30+rand(900) | – (0x407350 base ctor) |
| 9 | 0x4fc9a0 | 0x407e90 | 0x3c | tick+30+rand(150) | +0x14/+0x20/+0x2c = (ftol(W/2·65536), 0, ftol(H/2·65536)), +0x38 = 0 (0x407d40) |

- `W`, `H` are `game+0x14223/+0x14227`; the halves use `cdq; sub; sar 1` (truncation toward zero); the constant at `0x4fc970` is the double 65536.0.
- The vtable second entries are destructors (0x408810, 0x407980, 0x4079d0, 0x408600, 0x407390, 0x407ac0, 0x407e70).
- The names "min / start / K / source / attacking" for the slot 2/6 params come from the plan's reading of `0x4077e0` and remain inferred until CP12.

## Brain tick (`0x408c40`) and its caller (`0x464f80`)

- **Caller filter (native, disassembly only).** For player slots 0..9 in order: `[record] != 0`, `type ∈ {1,2,3}`, side byte `+0x146 != 10` (tested twice). Then `if (brain) 0x408c40()` at `0x465031`, and **always** `0x40b2c0(slot)` (knowledge refresh) at `0x465037`, followed by per-unit work. A record that fails the filter gets neither.
- **Tick body (native, executed).**
  1. If `[player] != 0` and `type == 2`: `countdown = countdown − 1`; if the result is `<= 0` (signed `jg`), set 30 and call `0x408830`.
  2. Slots 0..9 in order: if the pointer is non-null and `wake <= tick` as an **unsigned** compare (`ja` skip), call `vtable[0]`. The tick is re-read from `game+0x38a47` each iteration.
  3. `0x4089a0(brain, 1)`.
  Otherwise only `0x4089a0(brain, 0)`; the countdown is not decremented.
- **Wake prologues (native, executed).** Groups 1/2/3/4 store `tick + period` first thing. Groups 8 and 9 call `rand(900)` / `rand(150)` **before** reading the tick, then store `tick + rand + 30`. The no-op 0x407380 never writes, so group 5 is "called" on every AI tick. All wake arithmetic is modulo 2³².
- **Consequences.** The first AI tick runs every handler; the RNG order on that tick is rand(900) then rand(150). Group assignment first runs on the 30th brain tick of an active type-2 player (not the first) and every 30 after.

## Group assignment (`0x408830`) and set-group (`0x480250`)

- **Range.** `esi = [player+0x67]` to `[player+0x6b]` **inclusive** (`cmp esi, end; ja`), stride 0x118. The end is re-read every iteration. An empty range is `first > last` (unsigned).
- **Gate.** Units without `flags110 & 0x20` are skipped entirely (no state writes). Bit 0x20 is set at creation (`or ecx, 0x10021` at `0x485b61`); creation also puts the unit into group 0 (`0x480250(unit, 0)` at `0x485d29`).
- **State writes, for every gated unit, grouped or not.** If `def+0x245` bit 12 (cancapture): clear `0x80000`, set `0x40000`; else clear `0x40000`, set `0x80000`. Then clear `0x100000`, set `0x200000`. Two stores to `+0x110`.
- **Group test.** `unit+0xac` is compared as a **dword**; any non-zero value (including −1 dead and values such as 0x100) skips selection.
- **Selection (native order).** `flags110` bit 29 (structure) → armed (bit 31) ? 5 : 1; else `def+0x241` bit 6 (builder) → 4; else bit 11 (canfly) → 8; else signed word `def+0x1c0` (minwaterdepth) `> 0` → 7; else bit 31 → 3; else no call.
- **`0x480250(unit, g)`.** Uses the owner record `unit+0x96` → `[+0x78]`. If the old group is not −1 it searches the old group's vector (`+0x14` begin, `+0x18` end) for the unit pointer; if found, the **last element is copied into its slot** and the end shrinks by 4. If `g != −1` it appends at the end (growth path through `0x4b4f10` when capacity `+0x1c` is exhausted, order preserved). Finally `unit+0xac = g` (dword).
- **Definition bits (native, FBI parser).** builder = `def+0x241` bit 6 (`0x42c4b2`, `shl 6`), canfly = bit 11 (`0x42c6e1`, `shl 0xb`), cancapture = `def+0x245` bit 12 (`0x42ca48`, `shl 0xc` at `0x42ca72`), minwaterdepth = word `def+0x1c0` (`0x42cd82`, default −10000 from `0x4402f6`).

## Unit creation word (`0x485a40`, native, executed)

The unit initialiser writes `unit+0x110` in this order; 0x408830 later reads bits 0x20, 29 and 31 and overwrites 18–21. The weapon resets `0x48a160`/`0x489800`, `0x401070` and the final `0x480250(unit, 0)` at `0x485d29` do not touch the word.

| address | operation |
|---|---|
| 0x485a70 | set bit 28 |
| 0x485a8b | clear bits 29 and 14; bit 29 = (`def+0x22f` bmcode byte == 0) |
| 0x485ab3 | bit 31 = `def+0x241` bit 16 (`(and 0xffff0000) shl 0xf`: bits 17–31 shift out, so only bit 16 survives; the old bit 31 is cleared) |
| 0x485af3 | bit 30 = `def+0x241` bit 9 (`and 0x200; shl 0x15` after `and 0xbfffffff`) |
| 0x485b4c | `and 0xfffdf3e1; or 0x10021` (bit 0x20 is the assignment gate) |
| 0x485c3e | clear bits 8 and 9; bit 9 = (owner side byte `player+0x146` == `game+0x2a43`) |
| 0x485c90 | bits 18–19 = `def+0x241` bits 0–1 |
| 0x485cac | bits 20–21 = `def+0x241` bits 2–3 |
| 0x485cc5 | clear bits 26, 27 and 11; bit 11 = `def+0x241` bit 4 |
| 0x485cdb | `def+0x22e` byte > 1 (unsigned `jbe`): set bits 22–23 and clear 24–25; else clear 22–25 |

`unit+0x114` bit 0 = `def+0x241` bit 7 (0x485ad7) is also written here but is not part of `creation_flags`. The FBI keyword that sets `def+0x241` bit 16 was not re-read in this checkpoint (the research attributes it to the weapon1..3 entries); the creation copy itself is native.

## Port (`godot/ai_brain.gd`)

- `AIBrain.new(side, map_width, map_height, rng)` mirrors 0x408cb0 (handlers as Dictionaries with `k, group, vtable, think, kind, wake, side, params`).
- `tick(game_tick, player{p0,type}, units, definitions, group_lists, ids)` mirrors 0x408c40 and returns the event list (`assign`, `set_group`, `think` with wake and RNG state, `weapons` flag).
- `run_think` performs only the native prologue and then calls `think_hooks[k](brain, handler, tick)` if installed.
- `assign_groups(units, definitions, group_lists, ids)` is static; unit and definition Dictionary fields are documented in the file header (raw `flags241/flags245/minwaterdepth` or booleans `builder/canfly/cancapture`).
- `set_unit_group` mirrors 0x480250 including the swap-remove. Native finds the table through the unit's owner (`unit+0x96` → `[+0x78]`); the port edits whatever `group_lists` the caller passes, so the caller must pass the owner's lists.
- `creation_flags(flags110, {bmcode, flags241, byte22e}, local_side)` returns the whole `unit+0x110` word left by 0x485a40 (table above). Defaults: bmcode 1, flags241 0, byte22e 0.
- `creates_brain` and `runs_player_step` compare `type` and `side` as bytes and `p0` as a dword, like `tick()` and the native code.
- The RNG must be the shared 0x4b6c30 stream. If `new()` gets none, the first draw reports an error (`push_error`) and a private `wind_state.gd` instance is used instead of crashing; that private stream is not the game sequence.
- Nothing in the live world calls it yet; `opponent.gd` is unchanged.

## Evidence

- **Oracle `tools/native_ai_groups.py`.** Executes the original code in Unicorn and writes `local/ai/native-ai-groups.json` (ignored) and `analysis/native-ai-groups-validation.json`.
  - 600 assign cases: 13 profiles × 8 (structure armed/unarmed, land/air/sea builders, flyers, ships with minwaterdepth 20 and 0, negative depth armed, unarmed land, Commander with cancapture, already grouped, flag 0x20 clear) plus random mixes. Flags are random 32-bit words (so bits 18–21 start in every state), def words are random apart from the controlled bits, minwaterdepth takes −10000, −32768, −1, 0, 1, 2, 10, 255, 256, 32767 and random shorts, groups include −1, 0x100, 0x10000, −2. Ranges are full, sub-ranges and empty; group vectors start shuffled and about 8 % of members are left out of their vector (not-found path).
  - Original `0x408830`, `0x480250`, `0x406c10`, `0x406c40` run unmodified; dumped: every unit's flags and group dword (including units outside the range), all ten group vectors, and the `0x480250` call sequence.
  - Original `0x408cb0` (with `0x407350`, `0x407d40`, `0x4e43a0`) builds 32 brains; the handler table is dumped from memory.
  - Original `0x408c40` runs 32 sequences, 27,961 ticks: player `[p]`/type toggles (type 0/1/2/3, record word 0), initial countdowns 30/1/0/−5/random, tick starts 0, 1, 29, random, 0x7fffff80 and 0xfffffd00 (wake wrap), external RNG perturbations between ticks, 0–11 real units assigned on countdown ticks. Think calls observed: 0x4086d0 448, 0x4077e0 432, 0x4079f0 216, 0x408100 198, 0x407380 12,775, 0x407ae0 82, 0x407e90 153.
  - Original `0x485a40` (whole unit initialiser, including its two 0x4b6c30 draws, `0x48a160`, `0x489800`, `0x401070` and the final real `0x480250(unit, 0)`, which the oracle asserts) runs 400 times with random prior `unit+0x110`, `def+0x241` (bits 16, 9, 0–4, 7 forced on/off at random, high noise removed in every fifth case), bmcode 0/1/2/255/random, `def+0x22e` 0/1/2/3/255/random, owner side equal or not to `game+0x2a43`, and random bytes in the rest of the 0x249-byte definition. Weapon records are zero, so `0x489800` takes its early exit.
- **Comparator `godot/compare_native_ai_groups.gd`.** `AI_GROUPS_NATIVE 166987 / 166987 checks match` (assign flags 9,627, groups 9,627, vectors 6,000, call lists 600; construction 832; per tick RNG before/after, events, countdown, wakes 5 × 27,961; final sequence state 96; creation word 400).
  - A deliberate two-point mutation (rand(901) for group 8, unarmed structure → group 2) was caught: 142,442 / 166,587 (before the creation cases were added).
  - An audit applied 18 single mutations to the assignment/tick code; every non-equivalent one was caught by the comparator or the fixtures (the floor-vs-truncate hunter half only by the fixture, since the oracle's map sizes are all positive).
  - Creation mutations: dropping the `0xfffdf3e1` mask → 106 / 400 creation checks; `def+0x22e >= 1` → 325 / 400; ignoring the local-side bit → 192 / 400. Reading only bit 16 for bit 31 is equivalent and passes, as expected.
- **Fixtures `godot/test_ai_brain.gd`.** `AI_BRAIN 44 / 44 checks pass`: RNG n<2 rule, caller and creation filters (including byte truncation of type/side), handler table and hunter centre, first-tick order and draw order, 900-tick cadence (group 5 on every tick, assign at tick 29 then every 30), type 1 / record-word-0 paths, unsigned wake compare and wrap, negative countdown, hook after prologue, missing RNG fallback, selection order incl. s16 wrap of minwaterdepth, state writes, flag 0x20 gate, swap-remove and not-found append, creation word (mask, bits 30/31, local side, bits 18–21 and 11, `def+0x22e`). The missing-RNG fixture intentionally prints one `ERROR: AIBrain: no shared 0x4b6c30 random source` line on a passing run.

### Stubs in the oracle

| address | replaced by | why |
|---|---|---|
| 0x4b4f10 operator new | bump allocator | brain and handler objects only; group vectors are pre-reserved (capacity 128) so vector growth is not exercised |
| 0x4b4f20 operator delete | `ret` | not reached |
| 0x4089a0 weapon scheduler | `ret 4` + recorder of allow_commandfire | CP14 |
| think bodies | forced return after the wake store (0x4086e8, 0x407801, 0x407a10, 0x408127, 0x407b13, 0x407ebb) with ebx/esi/edi/ebp/esp restored | bodies are later checkpoints; the prologues are exactly the code before those addresses |

## Corrections to the plan

1. **Tick compare is unsigned** (`ja`), and wake arithmetic wraps; the plan's `wake <= tick` did not state signedness.
2. **Group assignment is not on the first tick.** The countdown starts at 30 and is decremented before the test, so the first `0x408830` call is on the 30th active type-2 brain tick.
3. **Brains exist for more than "present, type != 3".** `0x46489d` also builds one for a record whose word is 0. The caller loop still skips such records, so it has no effect on thinking.
4. **Handler params.** Slot 2 and 6 store five dwords (+0x14 = 3, +0x18 = 6, +0x1c = K, +0x20 = source group, +0x24 = 0); slots 3/7 store the slot index of the attack force (2/6). Slot 9 stores a map-centre vector three times, not only a period.
5. **"Clears only one bit of each 2-bit field" has no visible effect.** Clearing one bit and setting the other determines both bits, so the result is always move state 1 (MANEUVER, cancapture) or 2 (ROAM) and fire state 2 (FIRE AT WILL), whatever the previous value.
6. **The group field is a dword.** `unit+0xac` is tested and written as 32 bits, so the port must not store it as a byte.
7. **Set-group is swap-remove.** Group membership order (which later handlers iterate) changes when a unit leaves: the last member takes its place. Units enter group 0 at creation in creation order.
8. **The loop end is inclusive** (`player+0x6b` is the last unit, not one past it).
9. **U4 resolved: default minwaterdepth is −10000.** `def+0x1c0` is copied at `0x42cd82` from the movement record: either the MOVEINFO class (`def+0x1b6`) or FBI fields through `0x440340`, whose defaults come from `0x4402e0` (`mov word [eax+0xa], 0xd8f0`). Land units without the field are negative, so the plan's `>= 0` tests (water lattice in 0x40a5d0, the ×3 general-byte multiplier in 0x409730) are false for them, and group 7 needs a strictly positive value.
10. **The creation word is more than bits 28/29 and 0x10021.** 0x485a40 also derives bits 30 and 31 from `def+0x241` bits 9 and 16, masks the prior word with `0xfffdf3e1`, and later sets bit 9 (local side), bits 18–21 and 11 from `def+0x241` bits 0–4 and bits 22–25 from `def+0x22e` (table above).

## Limits

- Think bodies, weapon scheduler `0x4089a0`, knowledge refresh `0x40b2c0`, the damage hook `0x406f80` (writer of `brain+0xd`) and the AI context are not implemented.
- The caller loop `0x464f80` (a failed filter jumps to the loop increment `0x4655a6`) and the brain-creation test `0x46489d` were read, not executed; `runs_player_step` and `creates_brain` are covered by fixtures only.
- **RNG parity is prologue-only.** The think bodies draw further numbers (slot 8 at `0x407b8c` and 8 more calls, slot 9 at `0x407edf` and 3 more, slot 4 at `0x4083a9`/`0x4084ca`, slot 1 at `0x40875e`). The oracle stops each think after the wake store, so the per-tick "RNG after" match holds only for these stubs, not for a live game.
- The feeder body (`0x4079f0`) moves units between groups through `0x480460`; that path is not covered.
- `0x480250` growth/allocation and removals from groups other than 0 (cohesion `0x407560`, death `0x4867af`) were not executed; group vectors in the oracle had spare capacity. 0x408830 only reaches `0x480250` with old group 0.
- The creation oracle keeps weapon records zero, so the `0x489800` body past its early exit is not exercised (its own body does not write `unit+0x110`; its callees `0x4b07c0`/`0x4b0a70` on `unit+0x9a` were not traced).
- Negative map sizes for the hunter centre are covered by the fixture, not by the oracle.
- No live integration: nothing constructs an `AIBrain` in `construction_world.gd` or the viewer.

## Unknowns

- **U1.** Meaning of `flags110` 0x20 beyond "set at creation, gates assignment" (whether it is cleared for transported or unfinished units was not traced), 0x4000, 0x8000, 0x100; `unit+0x10e` bits. The creation sources of bits 9 (local side), 11, 22–27 and 30 are native, but their meanings and the meanings of `def+0x241` bits 0–4, 9 and `def+0x22e` are not established.
- `brain+9` is zeroed but no reader was looked for.
- Slot 2/6 param meanings (min/start/attacking) are inferred until CP12 executes `0x4077e0`.
- Whether any shipped code path puts units in group 9 (U10) is unchanged.
