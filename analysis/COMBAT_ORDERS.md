# Damage notifications, self-destruct and ground attack

This checkpoint closes three combat gaps:
- Damaged units now run their `HitByWeapon`/`TakeDamage` scripts, and closed buildings take reduced damage.
- Any unit can self-destruct (Ctrl+D).
- Units can fire at a map point (G, then click), and the D-gun can target the ground.

Each behavior was recovered by a reverse-engineering workflow: an analyst plus an adversarial verifier per topic, with the verifier's corrections applied.

## Damage notifications (`0x499cd0` → `0x489bb0` → `0x489ce0`)

### Recovered behavior

- **Weapon hits.** Every weapon hit goes through `0x499cd0(projectile, target, scale)`, whether direct (area ≤ 16 with a target) or splash (once per victim).
  - The damage is `trunc(base * scale)`, with attacker veterancy and the global double/halve flags.
  - The damage type is 1, or 2 for paralyzers.
  - The hit angle is `rint(atan2(proj.x − unit.x, proj.z − unit.z) · 32768/π) − heading`, and only its high byte is kept.
- **Armor and veterancy (`0x489bb0`).**
  - If the script set ARMORED (unit `+0x10e` bit 1) and the damage is below 30000, the damage becomes `(damage · damagemodifier16.16) >> 16`.
  - Target veterancy then scales by `(25 − k)·4/100`.
- **Application (`0x489ce0`).** A unit that is not alive or already dying ignores damage; otherwise the last attacker and damage type are recorded and the health word is reduced.
  - **Lethal hit (health ≤ 0).** A local owner (player types 1/2) gets the dying flag `0x4000` and no scripts.
  - **Non-lethal weapon hit (type 1).** `HitByWeapon(round(400·cos A), round(400·sin A))`, then `TakeDamage(clamp(health·100 / maxdamage, 0, 100))`. `A = byte << 8`, looked up in the 512-entry sine table.
  - **Threading.** Both calls start as queued threads (`0x4b0a70`, `runNow=0`), and a script whose eight threads are all busy drops them. Their return values never change the damage.
  - **Other damage types** (heal, paralyze, self-destruct, build) never call scripts.

### Implementation

- **Module.** `damage_notify.gd` provides `angle_byte`, `hit_arguments`, `health_percent` and `armored_damage`.
- **Damage.**
  - `CombatWorld.apply_damage(id, damage, source_raw, damage_type)` applies the ARMORED `damagemodifier` (FBI float × 65536, truncated) to weapon hits.
  - It keeps the health as a signed 16-bit word and records the last damage type.
  - Surviving victims queue `HitByWeapon` and `TakeDamage` without running them, skipping any the script lacks or when it has no free thread. The calls are listed in `notifications`.
- **Positions passed.** Direct hits pass the impact position, beams their head position, and splash victims the projectile position.
- **Veterancy and kill credit.**
  - The `+0xb8` kill word is incremented at `0x4869ca` when a fully built victim dies whose last attacker (`+0xf0`) belongs to another owner (`+0xf4 ≠ +0xff`).
  - Veterancy level is `min(kills/5, 5)`.
  - Attackers add `(6k + 100)/100` to weapon damage (`0x499dae`). Targets then scale all non-heal damage by `(25 − k)·4/100` after the armor modifier (`0x489bf3`).
  - `DamageNotify.attacker_veterancy`/`target_veterancy` implement these. `apply_damage` records `last_attacker` and `last_attacker_team`, and `kill_unit` credits the killer's `experience`, which firing spread and reload already use.
  - Death explosions carry no attacker, matching the synthetic projectile `0x49a0c0`.
  - The native comparator now checks the host veterancy functions against the original (the veterancy group matches 2,500 / 2,500). `test_damage_notify.gd` adds 6 checks: the veterancy factors, boosted damage from a 10-kill attacker, and kill credit that skips same-owner and unfinished victims.

### Evidence

- **Native oracle.** `native_hit_notify.py` runs the original `0x499cd0` end to end through `0x489bb0` and `0x489ce0`.
  - Only the script queue, stats, alert and network sends are recorded or stubbed.
  - It covers 3,720 cases: core, veterancy or global flags, paralyzer, inactive owner, and targeted boundaries added by an adversarial audit (the ARMORED 30,000 threshold, exactly-zero health and tie-free angle extremes).
  - `compare_native_hit_notify.gd` matches **18,601 / 18,601** checks: returned damage, the full packet, health, dying flag, the ordered script calls, and the sine table.
  - A mutation test (3 edited values) produced exactly 3 failures. The audit confirmed the hooks fire, the stack stays balanced after every stub, and the recorded instruction coverage reaches every in-scope branch.
  - This runs in `-Native`.
- **`test_damage_notify.gd`** passes 19 checks:
  - argument and angle cases for all four quarter directions and the diagonal;
  - heading subtraction, percent rounding and armor bounds;
  - live queueing on an `armflash`, with no scripts for non-weapon or lethal damage;
  - a closed `armsolar` (ARMORED) taking damage × 0.33333.

### Limits

- **Paralyzers.** They still apply damage in the host; the paralyze order is not implemented.
- **Inactive owners.** The owner branch (health clamped to 0, scripts run) does not arise in the host.
- **`damagemodifier` conversion.** The float-to-16.16 conversion is inferred.
- **Rounding ties.** The x87 `rint` rounds ties to even and the host `roundi` rounds them away from zero; no oracle case lands on a tie.

## Self-destruct (order handler `0x402010`)

### Recovered behavior

- **Order.**
  - The `SelfDestruct` background order (flags 0x40040) is toggled by Ctrl+D: when any selected unit already has it, it is removed from those units; otherwise it is added to all selected units.
  - The countdown is FBI `selfdestructcountdown & 7`, default 5.
- **Handler runs.** The first run happens on the unit update after the order is issued.
  - An already-expired order, or a countdown of 0, calls `0x489bb0(unit, unit, 30000, 3, 0)`. This check comes before the cancel check.
  - Otherwise, with count n > 0: play `count<n>`, set n − 1, and sleep 30 ticks.
  - At n == 0: play `count0`, mark expired, and sleep `rand(15)` from the game RNG.
- **Cancel.**
  - Before the first run, removal is silent.
  - Before expiry, it plays `canceldestruct`.
  - Once expired, the destructor's handler call takes the kill path and detonates at once.
- **Death.** Death follows the normal severity/`Killed` path. The death record's reason 3 makes `0x49b000` detonate `selfdestructas` (`def+0x224`) instead of `explodeas`.

### Implementation

- **Orders.** `CombatWorld.toggle_self_destruct(ids)`, `step_self_destructs` (run at the start of each combat step), `self_destruct_countdown` and `self_destruct_kill`.
- **Death explosion.** `kill_unit` picks `selfdestructas` when the unit's last damage type is 3.
- **Voice lines.** Requests are recorded in `voice_requests`.
- **Viewer.** Ctrl+D toggles self-destruct on the selected group, unit or Commander.

### Evidence

- **`test_self_destruct.gd`** passes 12 checks:
  - countdown parsing;
  - the voice sequence count5…count0;
  - death at `151 + max(1, rand(15))` ticks after the order, with exactly one RNG draw;
  - cancel before expiry (`canceldestruct`), and cancel during the final wait (immediate detonation);
  - silent cancellation of a mixed selection before the first run.
- **`--verify-self-destruct`** runs for both factions in NORMAL. A Flash or Raider counts down and dies after 159 ticks with the `BIG_UNIT` `selfdestructas` blast.
- **Oracle status.** The handler and scheduling come from verified disassembly and have not been executed natively.

## Ground attack and D-gun at a point (Suppress order `0x4038a0`, resolver `0x48a1e0`)

### Recovered behavior

- **Issuing the order.**
  - Attack mode with no enemy under the cursor issues **Suppress** at the clicked point.
  - The D-gun's AttackSpecial re-selects mode 3, retypes itself to Suppress (or Attack_Chase over an enemy) and uses weapon slot 3.
- **Point storage.** The point is stored as integer world X/Z words; a Z of 0x8000 is stored as 0x8001.
- **Target point.** Each weapon tick rebuilds the target as `(X<<16, max(bilinear terrain, sea level)<<16, Z<<16)`, with a strict `>` comparison. There is no SweetSpot, height offset or leading.
- **Aim.** Aiming, range, energy and reload are the same as for unit targets.
- **Order end.**
  - A normal fire event (0x400) moves the order to the back of the queue and re-arms it, so a lone ground attack fires until stopped.
  - A command-fire event (0x800) removes the order, so the D-gun fires once.
- **Out of range (event 0x1000).**
  1. A mobile unit moves to within R of the point, then `R −= rand(range/3)`.
  2. At R ≤ 0 the order finishes (code 9).
  3. A lone order then waits `30 + rand(30)` ticks and restarts.

### Implementation

- **Orders.** `CombatWorld.attack_ground(source, point)` and `command_fire_ground(source, point)` create ground orders with `point` and approach distance R. `ground_order` and `ground_target` implement the storage and resolver rules.
- **Order step.** Order stepping resolves ground targets through `order_target_point`, which also covers projectile deadlines, launch solutions and rocket targets. `step_ground_approach` applies the R shrink and restart rule.
- **Guards.** Automatic targeting does not replace a player's ground order.
- **Command fire.** It completes after its shot, as before.
- **Viewer.** G then click fires at the ground point. D-gun mode on empty ground fires a ground D-gun.

### Evidence

- **`test_ground_attack.gd`** passes 15 checks:
  - point storage and the 0x8000 conversion;
  - target height against terrain, sea level and outside the map;
  - a guarding Stumpy keeps shelling the ground (not the nearby enemy) until stopped;
  - an out-of-range point starts an approach, consuming an RNG draw and shrinking R;
  - the unit closes on the point.
- **`--verify-ground-attack`** runs for both factions in NORMAL:
  - a Stumpy or Raider fires 7 shots at a ground point over 360 ticks and keeps suppressing;
  - the Commander D-guns the ground under an enemy, fires exactly once, the order completes, and the enemy dies.
- **Oracle status.** The Suppress state machine and approach are from verified disassembly and not executed natively.

### Limits

- **Movement.** The move request "within R of the point" is approximated by a path to the point at distance R.
- **Queue and events.** The order queue (back-of-queue cycling with other orders) and slot release on unit event bits are not modelled.
- **Range check.** It uses the host's distance test rather than `0x49aa80`.
- **Selection.** Air-weapon rejection and hover-unit selector rules are not applied.
