# COB VM parity: RAND, EMIT_SFX, slot exhaustion, optional weapon callbacks, health read

Checkpoint CP0 of the level-two plan. It closes the interpreter gaps that kept damaged smoke (`SmokeUnit`), Pyro's pilot light and hover wakes from running, and replaces the permanent "thread capacity" fault with the original drop behaviour.

Addresses refer to `TotalA.exe` SHA-256 `3b9c0fadabf3dc67ed5f05a70f1e1505a0c65deadd1a3c930adfe30e2a84995e`.

## Recovered behaviour

### RAND (opcode `0x10041000`)

The interpreter handles RAND itself at `0x4b15bd`; it never calls an engine callback:

- It pops **high**, then **low**, and calls `0x4b6c30(high - low + 1)`. The result is `low + value`, pushed as a 32-bit word.
- `0x4b6c30` returns 0 without touching the seed when the bound is below 2 (`cmp edi, 2; jge`, a signed compare). A negative span or `low == high` therefore returns `low` and does not draw.
- Otherwise it advances the shared seed at `0x51fc88` with Park-Miller (`seed * 16807 mod (2^31 - 1)`). It uses a multiply-high by `0x69c16bd`, maps a non-positive result to `+0x7fffffff`, stores the seed and returns `seed % bound` (unsigned `div`).
- The game seeds `0x51fc88` through `0x4b6ca0`: `(x ^ 0x66e29572) | 1`. The only caller is `0x49719d`. A zero seed (the untouched Unicorn image) turns into the constant `0x7fffffff`.

`godot/wind_state.gd` `bounded_random` already implements this generator. `test_cob_rand.gd` transcribes the 32-bit native routine and finds no differences over 200,000 random 32-bit seeds, including seeds with the high bit set.

### EMIT_SFX (opcode `0x1000F000`, one piece operand)

Handler `0x4b12bd` pops the SFX type and calls engine vtable `+0x30` (slot 12, stdcall, `ret 8`) with `(piece, type)`, where piece is the script piece index taken from the operand. The script sees nothing further. In the unit scripts, SmokeUnit emits `256|1` or `256|2`; the armch/corch wake loops emit 3 and 5. Rendering these effects is future renderer work.

### Slot exhaustion

- `0x4b08c0` (allocate) returns -1 when the function index is invalid or all eight slots are busy.
- The host helper `0x4b0b00` returns 0 when allocation fails. If the caller passed a completion object, it first calls that object with 0 (`0x4b0b11..0x4b0b1d`). The name-based wrappers `0x4b0940` and `0x4b0a70` forward to it, and unknown names resolve to index -1, so they fail the same way.
- The synchronous helper `0x4b0c40` (weapon queries) returns 0 and leaves the caller's local, the query's initial value, untouched.
- `START_SCRIPT` `0x4b18b0`: when allocation fails (`jl 0x4b18f8`) the parameters are **not popped**; they stay on the caller's stack. The PC advances and the caller keeps running.
- `CALL_SCRIPT` `0x4b191d`: same as START_SCRIPT when allocation fails, except it stores `-1` as the wait slot (`[esi+0x18]`) and still enters the call state `0x2800000`. RETURN (`0x4b1a0a`) and SIGNAL (`0x4b1abc`) release call-state threads only when their wait slot equals the finishing slot. A dropped CALL_SCRIPT therefore stays blocked until a signal kills it.
- Nothing faults and nothing is logged.

### Optional weapon callbacks

The weapon slot index `(weapon+0x1b >> 2) & 3` selects the name from the tables at `0x509678` (FirePrimary/Secondary/Tertiary) and `0x509688` (AimPrimary/Secondary/Tertiary).

- **Fire**: the three projectile launchers call `0x4b0940("Fire*", callback 0, run-now 0)` at `0x49cb94`, `0x49cd4f` and `0x49cf73`. They do this after the projectile fields are set, and they ignore the return value. A script without FirePrimary (corpyro) still launches, and reload proceeds.
- **Aim**: the aim update (`0x49e31c` / `0x49e386`) clears the aim result (`[esi-0x13] = 0`) and calls `0x4b0a70("Aim*", completion object, run-now 0, 2 args)`. A missing or dropped Aim reports 0, so the weapon never counts as aimed and never fires.
- **Query/AimFrom**: `0x43e240` and `0x43e2e0` call `0x4b0bc0` → `0x4b0c40` with an initial local (0 for Query, -1 for AimFrom). A missing or dropped query keeps that value. The AimFrom -1 → Query fallback was already in `weapon_queries.gd`.

Aim and Fire are started with run-now 0: they first execute on the unit's next scheduler pass. The host `weapon_cycle.gd` still starts them immediately. That is a separate timing question outside CP0, recorded below as a follow-up.

### GET_VALUE 4 (HEALTH)

The value-get callback is vtable slot 17 (`+0x44`). The engine vtable is at `0x4fd698` and the function at `0x480770`, which switches on `key - 1` through the jump table at `0x480ac4`. Key 4 goes to `0x4807ca`:

```
movsx eax, word [unit+0x108]      ; health (signed 16-bit)
eax = eax * 100
div dword [definition+0x1fa]      ; maxdamage, unsigned, edx = 0
```

The unit is `[[this+0x540]+0xc]`, its definition pointer is the dword at `unit+0x92`, and the callback returns with `ret 0x14`.

So `health_read = ((signed16(health) * 100) as u32) / maxdamage`, truncated and **not clamped**.

Review evidence: `tools/native_health_read.py` executes `0x480770` itself in Unicorn with key 4. It runs against synthetic unit and definition records, covering 2,985 health/maxdamage pairs: the full signed word range, values above 16 bits, and maxdamage up to `0xffffffff`. `godot/compare_native_health_read.gd` matches `VM.health_read` on all 2,985 pairs. This checks the formula directly; the damaged-seeded oracles only stub the read with 100/50/20. Separately, the real `0x4b6c30` run in Unicorn agrees with `bounded_random` on 3,007 seed/bound pairs, including 0, `0x7fffffff`, `0x80000000`, `0xffffffff` and random high-bit seeds. Health above maxdamage reads above 100, and negative health wraps through the unsigned division. The 30-tick sampler (`sample_health_percent`) and the TakeDamage percent clamp; this read does not.

## Implementation

| File | Change |
| --- | --- |
| `godot/cob_vm.gd` | RAND (`random_source().bounded_random`); the injected `rng` defaults to a private `wind_state.gd` instance. EMIT_SFX appends `[tick, piece, type]` to `sfx_events` (bounded at `SFX_EVENT_LIMIT` = 4096, with an unbounded `sfx_count`) and calls the optional `sfx_callback(piece, type)`. `allocate`/`invoke` return -1 on a full VM, increment `dropped_calls` and record a `drop` event. START_SCRIPT/CALL_SCRIPT check for a free slot before popping; a dropped CALL blocks with `wait_slot` -1. New static `health_read(health, maxdamage)`. |
| `godot/weapon_cycle.gd` | No "Missing weapon callback" fault. A missing Aim never aims; a missing or dropped Query uses piece 0; a missing Fire still produces the shot. |
| `godot/weapon_queries.gd` | A dropped query returns its initial value. |
| `godot/construction_world.gd` | Every script (world-owned and external) gets `vm.rng = game_random`. `read_values[4]` is set from `VM.health_read(unit.health, maxdamage)` at creation and at the start of every world tick, before scripts step. |
| `godot/combat_world.gd` | HitByWeapon/TakeDamage no longer pre-check free slots; `invoke` drops and counts them. |
| `godot/test_cob_vm.gd` | The ninth-slot check now expects a silent drop instead of a fault. This file was outside the owned list, but the mandated behaviour change required a one-line edit. |

Health is fed once per tick, not read live. Callbacks started immediately by the host between damage and the next world tick (only `Killed`) would see the previous tick's value. Killed scripts do not read HEALTH.

## Native oracle harness

- `tools/native_cob_reference.py` `NativeReference`, inherited by `SolarReference` and `FactoryReference`, now also:
  - stubs slot 12 (`ret 8`) and records `sfx` as `[tick, piece, type]`, where tick counts `step()` calls;
  - offers `seed(x)` (the 0x4b6ca0 formula), `write_seed` and `rng_seed`, plus `--seed` on the Commander CLI;
  - returns `False` from `invoke` for an absent callback or a full VM, recording `dropped`;
  - adds `free_slot()`.
- Existing `snapshot()` payloads are unchanged. SFX, seeds and drops go at the top level of the trace, so other comparators are unaffected.
- `tools/native_mobile_reference.py --damaged`, `tools/native_factory_reference.py --damaged` and `tools/native_firing_reference.py --damaged` implement the **damaged-seeded** scenario:
  - 600 ticks;
  - seed input `0x1234` (word `0x66e28747`);
  - health read 100 from tick 0, 50 from tick 200, 20 from tick 400;
  - the usual callbacks, repeated 300 ticks later.
- corpyro is added to the damaged mobile set and to the firing unit list.
- The firing reference records a dropped query as piece 0.
- `tools/native_cob_overflow.py` and `godot/compare_native_cob_overflow.gd` run a synthetic multi-function script:
  - eight busy slots, a dropped host start, dropped START_SCRIPT and CALL_SCRIPT, and a signal release;
  - seeded RAND into statics, and EMIT_SFX;
  - pc, sp, the first four stack words, state and wait slot compared on every snapshot.
- The comparators `compare_native_units.gd`, `compare_native_factory.gd` and `compare_native_firing.gd` accept `--damaged`. They seed the host RNG from the trace's `seed_start`, apply the trace's health schedule, and compare the full `sfx` list, `sfx_count`, final seed and drop count in addition to every snapshot.
- `tools/verify_cob_parity.ps1` regenerates and compares all of the above.

## Evidence

`test_cob_rand.gd`: 33 / 33 checks.

- RAND against native 0x4b6c30 (200k seeds) and bounded_random, including pop order and bound < 2 with no draw.
- Shared-RNG ordering across VMs, and the lazy private RNG.
- EMIT_SFX recording, the renderer hook and the bounded list.
- Host, START and CALL overflow drops, including stack contents and wait slot -1.
- Health read formula edge cases.
- Optional weapon callbacks: no FirePrimary still shoots and reloads (3 shots in 70 ticks at a 30-tick reload); no AimPrimary never fires; no QueryPrimary uses piece 0.

### Native comparison results

All runs finished with 0 VM faults (`tools/verify_cob_parity.ps1`).

| Comparison | Snapshots | Extra |
| --- | --- | --- |
| Synthetic overflow/RAND/SFX (`compare_native_cob_overflow.gd`) | 73 / 73 | pc/sp/stack/wait slot per slot; SFX and final seed match |
| Arm Commander lifecycle (`compare_native_cob.gd`) | 464 / 464 | unchanged baseline |
| Mobile, healthy (24 level-one units) | 7,320 / 7,320 | 0 SFX, seed unchanged |
| Mobile, damaged-seeded (24 level-one units plus corpyro, 600 ticks) | 15,227 / 15,227 | 200 SFX events and final seeds match for all 25 |
| Factory, healthy (4 plants plus 6 spin cases) | 3,642 / 3,642 | |
| Factory, damaged-seeded (4 plants, 600 ticks) | 2,436 / 2,436 | 32 SFX events and seeds match |
| Firing, healthy (21 units, now including corpyro) | 6,793 / 6,793 | query pieces match |
| Firing, damaged-seeded (21 units, 600 ticks) | 13,549 / 13,549 | 152 SFX events and seeds match; the commanders emit none in this window |

Damaged-seeded traces start from seed word `0x66e28747`. Units whose only RAND use is SmokeUnit end at `0x2ddf03a4`. corpyro's pilot light also draws every flicker, so it ends at `0x77f97520`, and the host reproduces it exactly.

`test_cob_health_feed.gd` (7/7) covers the live world:

- a finished healthy armflash reads 100 and neither smokes nor draws;
- one damaged to a third reads the fed value, emits only 257/258, and advances `world.game_random`;
- the feed refreshes on the next tick;
- an unfinished frame reads construction health without smoking or drawing.

Mutation checks: swapping RAND's pop order or EMIT_SFX's piece/type makes the firing comparators fail.

## Follow-ups (not changed here)

- A dropped or missing Aim leaves `weapon_cycle.aim_id` at -1 and `aimed` false. `combat_world` only calls `aim()` again when the target angle changes. A transient eight-slot overflow on a stationary target therefore stalls that weapon until the angle moves. The native re-aim branch at `0x49e33d..0x49e386` appears to re-request while unaimed, so its flag conditions should be recovered before changing the cadence.
- Fixed at integration: `construction_world.factory_build_position` now uses piece 0 when `QueryBuildInfo` is dropped because all eight slots are busy, matching the initial local that native `0x4b0c40` keeps. `test_cob_health_feed.gd` checks this. A missing `QueryBuildInfo` or a query that does not finish immediately still gives no position.
- `sfx_events` ticks are VM-local step counts. They are not world ticks for scripts created mid-game, so a renderer must use `sfx_callback` or offset by the creation tick.
- The overflow comparator checks `dropped_calls >=` the native host-start drops, because the native harness cannot count in-script drops. Host-start drops are compared exactly through each snapshot's `started` field.

- Aim and Fire are native run-now 0 starts (`0x49e31c`, `0x49cb94`), but `weapon_cycle.gd` runs them immediately. The oracle harness also starts them immediately, so VM parity holds; the live cadence needs a separate world-level check.
- Native `0x4b0b00` sets the initial stack pointer to `argcount - 1`: 2 for Aim, and 3 for synchronous queries via `0x4b0c40`. The host and oracle use -1 with args preseeded in locals. Scripts only index locals, so existing traces match, but a script that pops below its locals would differ.
- Renderer: map SFX types (`256|n` smoke, 3/5 wakes, etc.) to effects; the hover `setSFXoccupy` callback is not yet sent by the world.
- COB RAND now shares `world.game_random`. Damaged units draw from the same sequence as combat orders and burst spread, as in the original. Golden traces that relied on smoke never running may shift.
