# Weapon Aim requests: request bit, completion result and tolerance

This checkpoint replaces the port's provisional aim/re-aim rules with the original per-slot weapon state machine. It covers what happens after a dropped, zero-returning or killed `Aim<slot>` call, when a turret weapon fires on a stale aim, and when Aim is issued again.

The research spec was read from the disassembly first. Every rule below was then re-read at the listed addresses and run unmodified under Unicorn.

## Weapon entry (`unit + 4 + slot·0x1c`)

| Offset | Size | Meaning |
|---|---|---|
| `+0` / `+2` | word | Target: a unit index with `0x8000`, or ground X/Z words (set by `0x48a060`/`0x48a0a0`/`0x48a0f0`) |
| `+4` | object | Completion object with vtable `0x4fd6f0`. Its `+4`, which is entry `+8`, is the **result** |
| `+0x0c` | dword | Weapon definition |
| `+0x14` | word | Reload countdown |
| `+0x16` / `+0x18` | word | Stored aim heading and pitch |
| `+0x1a` | byte | Stockpile count (read by the `0x10000000` gates) |
| `+0x1b` | byte | Flags: bit 0 = Aim **requested**, bit 1 = present, bits 2–3 = slot |

Setting or clearing a target does not touch bit 0 or the result.

## Per-slot update (`0x49e1a0`, called at `0x48adda`)

The update runs once per slot, with `F = def+0x111`:

1. **Presence.** Slots without the present bit (bit 1) are skipped.
2. **Reload.** A nonzero reload word is decremented. This happens before the target check, so it also counts down with no target.
3. **Target.** If `0x48a1e0` finds no target, bit 0 is cleared and the slot is skipped (`0x49e1ea`). A dead unit target also has its words cleared and starts `TargetCleared(slot)` with run-now 0. Ground targets always resolve.
4. **Callback.** A slot whose `def+0x60` fire callback is 0 is skipped.
5. **Aim issue.**
   - **Turret (`F & 0x80000`), bit 0 clear.** Solve the angles:
     - ballistic weapons use AimFrom `0x43e2e0`, `atan 0x4b715a − unit heading` and pitch `0x49a890` (this fails on `0x8000`);
     - otherwise lineofsight (`F & 1`) uses `0x49d910`, which always succeeds;
     - any other turret weapon fails the solve.

     On success the update stores heading and pitch, sets result = 0, then calls `0x4b0a70("Aim<slot>", &entry+4, run-now 0, argc 2, h, p)` and ignores its return (`0x49e31c`). It then calls the network echo `0x456200` and sets bit 0 (`0x49e3ab`). Bit 0 is set even when the start was dropped or the function is missing. **A failed solve issues nothing and leaves bit 0 clear.**
   - **Otherwise, `F & 0x10` (vlaunch), bit 0 clear.** The stockpile gate applies: when `F & 0x10000000`, count `+0x1a` must be nonzero. The update sets result = 0, starts `Aim<slot>(0, 0)` (`0x49e386`), calls the network echo and sets bit 0. The stored angles are not written.
   - **Neither bit set.** No Aim is ever issued.
6. **Fire attempt (`0x49e3ae`).** This runs in the same update, straight after any Aim issue, and only when the reload word is 0.
   - The range gate is `0x49aa80`. On failure it sets `unit+0xbb |= 0x10` (`0x49e53a`).
   - Stockpile weapons need count `+0x1a` nonzero. Other weapons need stock at or above `def+0xc0` energy and `def+0xc4` metal.
   - The update then calls `def+0x60(unit, entry, 0x48a190 target, point)`.
   - On success, a stockpile weapon decrements its count and calls `0x41c150`. Any other weapon writes the reload settlement (`0x49e468..0x49e4ee`) and later pays through `0x4012a0`.
   - Either way it sets `unit+0xba |= 0x400` (or `0x800` when `F & 0x4000000`).

### Script start and completion

- **`0x4b0a70`.** This looks up the name and passes −1 when the name is missing. `0x4b0b00` → `0x4b08c0` then allocates one of eight slots.
- **Failed start.** A missing function or no free slot makes `0x4b0b00` call the completion synchronously with 0 (`0x4b0b11..0x4b0b1d`) and return 0.
- **Run-now.** With run-now 0 the new thread (state `0x1000000`) is not stepped inside the start. The unit update calls the scheduler pass `0x4b0d60(1)` at `0x48adeb`, right after `0x49e1a0`. **An Aim issued in tick T therefore first runs in tick T's own scheduler pass: after that update's fire attempt and before the next weapon update.**
- **Completion `0x481490`.** It sets result = 1 when the value is nonzero; a value of 0 leaves the result unchanged. It is invoked by RETURN (`0x4b19d0`) and by the failed start. It is never invoked by a SIGNAL kill (`0x4b1a75..0x4b1aab`) or a bad opcode.

## Fire callbacks

### Turret `0x49d580`

1. The callback returns 0 when bit 0 is clear or the result is 0 (`0x49d590`/`0x49d59b`).
2. It solves the angles again from the current AimFrom and target point. On failure it clears bit 0, sets `unit+0xbb |= 0x10` and returns 0 (`0x49d65b`).
3. It runs the tolerance check `0x49d880` against the stored angles. On failure it clears bit 0 and returns 0 (`0x49d68a`). **Aim is issued again on the next update, not in this one.**
4. It queries the muzzle through `0x43e240`, and the stored heading becomes absolute: `+= unit heading` (`0x49d6b4`).
5. Spread (`0x4b6c30` ×2) perturbs both stored angles when the accuracy term is nonzero.
6. It picks a launcher:
   - lineofsight or selfprop (`0x100000`) uses `0x49c9c0`;
   - ballistic uses `0x49cde0`;
   - anything else gets no launch.
7. On a successful launch it sets result = 0, clears bit 0 and returns 1 (`0x49d78b..0x49d797`). **A failed launch returns 0 but keeps bit 0 and the result, and leaves the absolute, perturbed heading stored.** The next attempt then usually fails tolerance.

### Tolerance `0x49d880`

- **Tolerance 0.** When `def+0x106 == 0`, both limits are `2000` if `unit+0x110 & 0xc`, and `150` otherwise. `pitchtolerance` is ignored in this case.
- **Nonzero tolerance.** Heading uses `def+0x106`. Pitch uses `def+0x108`, or `def+0x106` when that is 0.
- **Comparison.** The check passes when `|int16(stored − new)| ≤ limit` on each axis. The limits are unsigned words.

### Vlaunch `0x49db70`

- **Gate.** The callback is gated only by result ≠ 0 (`0x49db7b`); bit 0 is not tested.
- **Angles.** It stores the absolute muzzle-to-target line angles, then launches through `0x49cc20` (after the `0x49d120` check when `F & 0x40000000`).
- **Success.** It clears the result and bit 0 (`0x49dd30..0x49dd38`). `edi` is 0 on both network paths, which confirms the spec's inferred value.

### Fire script starts

The launchers `0x49cb94`/`0x49cd4f`/`0x49cf73` start `Fire<slot>` through `0x4b0940(name, 0, run-now 0)` after creating the projectile. The launchers `0x49cbeb`/`0x49cda6`/`0x49cfca` also start `RockUnit(−atan…, …)` with run-now 0.

## Corrections to the research spec

- **Failed turret solve.** It issues no Aim and does **not** set bit 0. The spec's pseudo-code was right, but the port had to be explicit about this.
- **Network echo.** `0x456200` is called for both the turret and the vlaunch issue.
- **Stockpile gate.** The vlaunch stockpile gate is `!(F & 0x10000000) || count != 0`. Stockpile weapons also skip the resource test at the fire attempt, and they decrement the count instead of writing the reload.
- **Vlaunch clear.** The value that clears the vlaunch result is confirmed as 0 on both network paths; the spec had marked it as inferred.
- **Failed launch in the turret callback.** It keeps bit 0 and the result, with the heading already absolute and spread-perturbed. The spec did not cover this.
- **Aim thread timing.** The Aim thread runs in the **same** tick's scheduler pass (`0x4b0d60` at `0x48adeb`), after the fire attempt. The spec only said "next scheduler pass".
- **`Fire<slot>` start.** It is also run-now 0, and the launchers additionally start `RockUnit`.
- **Undefined Aim.** A missing `Aim<slot>` behaves exactly like a dropped start: bit 0 is set and the result stays 0.

## Port (`godot/weapon_cycle.gd`, `godot/combat_world.gd`)

- **State.** `requested` is bit 0 and `result` is entry `+8`; `aimed` is `result != 0`. `heading`/`pitch` are the stored words, `next_burst` encodes the reload word, and `flags_byte()` rebuilds `+0x1b`.
- **`update(context)`.** This is one `0x49e1a0` slot pass: completions, the target state (`TARGET_NONE`/`TARGET_VALID`/`TARGET_DEAD`), the Aim issue when not requested, and then a fire attempt at reload 0 through `fire_turret` or `fire_vlaunch`.
- **Completions.** All started Aim ids stay tracked until they complete or their thread disappears. Any RETURN with a nonzero value sets the result; SIGNAL kills and faults do not.
- **Removed port rules.**
  - the angle-change re-aim;
  - the `denied` re-aim after a held attempt;
  - `aimed = result == 1`;
  - the same-step re-aim after a shot;
  - the immediate Aim run.
- **`combat_world.gd`.**
  - It computes `turret_solve` (`0x4b715a` rounding in `native_atan`, and `0x49d910` line angles in `line_angles`) from the current AimFrom and target point.
  - It passes the spread and line-angle callables to `update`.
  - It takes the shot heading and pitch from the callback's stored words.
  - When the target unit is gone, it sends one `TARGET_DEAD` update before ending the order, which starts `TargetCleared` and clears the request.
- **Timing.** `Aim` and `Fire` are started with `immediate = false`. The host steps the VM before the combat step. The first run therefore falls between the issuing update and the next one, the same weapon-update ordering as the original. Only other same-tick host work (movement, other units) sees the new thread's first effects one pass later than the original.

## Evidence

- **`tools/native_weapon_aim.py`.**
  - **Unmodified code.** The oracle runs, unmodified: `0x49e1a0`, `0x48a1e0` (with `0x485070` terrain and the TargetCleared start), `0x49aa80`, `0x49a890`, `0x4b715a`, `0x49d910`, `0x49d580`, `0x49d880`, `0x4b6c30`, `0x49db70`, the callback installer `0x49e010`, `0x4b0a70` → `0x4b0b00` → `0x4b08c0` against a fake eight-slot context, and the completion vtable `0x481490`.
  - **Recorder stubs.** Stubs replace:
    - the piece queries `0x43e2e0`/`0x43e240`/`0x43e3c0`, which write the scenario points;
    - the launchers `0x49cde0`/`0x49c9c0`/`0x49cc20`, which record the stored angles and return the scenario result (their Fire/RockUnit starts are not modelled);
    - the payment `0x4012a0`;
    - the network echo `0x456200`.
  - **Fake COB layer.** A scripted layer replaces the scheduler pass `0x4b0d60`. It completes with a value 0, 1 or 2 after N passes by calling the real vtable, kills without a callback, never finishes, or fills every free slot so the original allocator drops the start.
  - **Cases.** There are 8 hand-built cases (drop, zero-return and kill stalls, return 2, tolerance 150/2000/explicit, slow aim) and 360 random ones:
    - weapons: ballistic, lineofsight and selfprop turrets, vlaunch, and unsolvable turrets;
    - tolerance: 0, 1, 100, 150, 2000, 6000 or 40000, with pitch tolerances;
    - `unit+0x110` bits;
    - moving and turning units, moving targets and target switches;
    - ground targets and target deaths;
    - launch failures, resource gaps and missing Aim functions.
- **`godot/compare_native_weapon_aim.gd`.** It drives `weapon_cycle.gd` with the same fake responses and compares, per tick: the flags byte, the result, the stored heading and pitch, the reload, the Aim/TargetCleared starts (name, args, started), attempts, launches (stored angles), the `+0xbb` bit, the network echo count, the callback count and the RNG seed.
  - It matches **656,272 / 656,272** checks over 368 cases and 54,720 ticks.
  - Coverage: 866 Aim starts, 89 dropped, 674 callbacks, 37,996 attempts, 393 launches, 53 TargetCleared starts, 7,545 range flags and 144 tolerance clears.
  - Output: `analysis/native-weapon-aim-validation.json`.
- **Mutations.** Four deliberate port mutations were all caught: completion `== 1`, no tolerance clear, re-aim while the result is 0, and re-aim in the shot update. The native mismatches were 27,626, 14,690, 145,650 and 27,776, and `test_weapon_aim.gd` also failed for each.
- **`godot/test_weapon_aim.gd`.** It passes **43 / 43**: stall after drop, zero, kill and never; target-loss recovery; TargetCleared; run-now 0; return 2; re-aim after the shot and after a tolerance failure; no angle-change re-aim; the tolerance limits; re-solve failure; launch failure; vlaunch; missing Aim; and Fire run-now 0.

## Limits

- **Callbacks not ported.** `0x49d9c0` (the non-turret lineofsight/selfprop callback) and `0x49dd60` (dropped) are not ported. Weapons with neither the turret nor the vlaunch flag are hosted as turrets, whereas the original never issues Aim for them.
- **Stockpile.** Stockpile gating and counts (`+0x1a`, `0x41c150`) are not modelled in `weapon_cycle.gd`.
- **Host inputs.** `combat_world.gd` still uses a host range test instead of `0x49aa80` and passes `unit+0x110 = 0`; the source of bits `0xc` is unidentified. It also keeps the host rule "no fire while moving" (`permit`).
- **Other gaps.** Launchers do not start `RockUnit`. `unit+0xba` shot flags are not modelled.
