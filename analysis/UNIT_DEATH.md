# Unit death

Weapon kills now follow the original death pipeline instead of simply deleting the unit at zero health.

## Recovered original behavior

- **Damage application `0x489ce0`.** Subtracts damage from the signed health word at `unit+0x108`. When health drops below 1 for units owned by controller type 1 or 2, it sets unit flag `0x4000` (dying) and keeps the negative health; other controllers clamp to 0. A dying unit ignores further damage. The last damage type byte is stored at `+0xf5`. Weapon hits (type 1) also call the `HitByWeapon` and `TakeDamage` scripts, which the host does not call yet.
- **Health sampler.** In the per-unit update, on game ticks divisible by 30, the previous sample moves to `+0xf7` and a new one is taken at `+0xf6`: `(health × 100 as unsigned) / maxdamage`, clamped to 0–100. Both start at 0 on creation.
- **Death `0x4864b0`.** Runs during the dying unit's own update, after its weapons and script. Severity is `((−health × 100 as unsigned) / maxdamage + previous percent) / 2`, clamped to 1–100. The engine then calls `Killed(severity, corpsetype)` synchronously through `0x4b0bc0`; the script writes the corpse type into its second local. A unit that is not fully built (`+0x104` build fraction nonzero) gets corpse type 0.
- **Death handling `0x4866d0`.** It updates kill statistics and removes the unit from the collision grid and systems. For a severity above 0 on a completed unit, `0x49b000` builds a synthetic projectile of the unit's `explodeas` weapon (`selfdestructas` for self-destruct) at its position and sends it through impact dispatch `0x499eb0`, which splashes. A nonzero corpse type is passed to `0x486360`.
- **Corpse `0x486360`.** Starts from the definition's `corpse` feature (`def+0x1bc`). Each corpse-type step above 1 follows the feature's `featuredead` (`+0xf4`), for example from the wreck to its heap. The result is placed at the unit's cell through `0x423c50`.
- **`EXPLODE` opcode.** Interpreter opcode `0x10071000` pops debris flags and calls engine vtable offset `0x34` with (piece, flags). Its effect is visual debris.

## Implementation

- `cob_vm.gd` supports `EXPLODE`, recording `[piece, flags]` calls in `explosions`.
- `combat_world.gd` routes all weapon damage through `apply_damage`: negative health, the dying flag and damage immunity. Deaths are queued and processed at the end of the combat step by `kill_unit`. It computes severity, runs `Killed` for the corpse type and debris list, zeroes the corpse for unfinished units, and removes the unit. It then applies the `explodeas` splash from the unit's collision position and records the death: type, severity, corpse type, corpse feature, position and debris. Explosion kills join the same queue, so chains resolve in one step.
- `construction_world.gd` keeps `health_percent` and `previous_health_percent` and samples them every 30 ticks.

## Evidence

- `native_killed_reference.py` and `compare_native_killed.gd`: 352 of 352 cases match the original interpreter. That is 32 level-one unit and structure scripts at 11 severities around the script thresholds, checking the returned corpse type, the order and flags of every `EXPLODE` call, and hidden pieces. Every script maps severity ≤25 to corpse type 1, ≤50 to type 2, and >50 to type 3. Summary: native-killed-validation.json; runs under `-Native`.
- `test_unit_death.gd` passes 35 checks in NORMAL:
  - **Severity:** arithmetic fixtures.
  - **Flash deaths** producing each corpse type: pending state, damage immunity, removal, the recorded `armflash_dead` corpse and debris, `BIG_UNITEX` splash reaching a unit 30 units away but not one 200 away.
  - **Unfinished units:** no corpse and no explosion.
  - **Chains:** a chained death from another unit's explosion.
  - **Sampler:** the 30-tick health-percent shift.

## Limits

- **Corpses.** Recorded but not yet placed as map features. Wreck feature definitions, footprint writing, blocking, projectile collision with wreck heights, rendering and reclaim are the next checkpoint.
- **Debris.** `EXPLODE` debris is not simulated or rendered.
- **Timing.** Deaths resolve at the end of the host combat step rather than inside each unit's update. Order relative to other units in the same tick is approximate.
- **Other death sources.** Self-destruct (`selfdestructas`, reason 3), kill statistics, `HitByWeapon`/`TakeDamage` on damage, and non-weapon deaths are not connected.
