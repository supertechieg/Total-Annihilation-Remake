# Core level-one combat roster

The Core Thud (`corthud`), Leveler (`corlevlr`), Storm (`corstorm`), Slasher (`cormist`) and Crasher (`corcrash`) now fight with the existing cannon, rocket and guided-missile hosts, alongside the Raider that was already supported. Their weapons match Arm counterparts in class: Thud's plasma cannon is the Hammer's class (speed 210, minbarrelangle -35), Leveler's is a ballistic light cannon (speed 280, AoE 84), Storm fires self-propelled unguided rockets like Rocko, and Slasher/Crasher fire guided tracking missiles like Samson/Jethro. Combat reads everything from each unit's `weapon1` definition; no Core-specific combat logic was added.

The three Core laser units (Instigator `corgator`, Weasel `corfav`, A.K. `corak`) and Arm's Jeffy (`armfav`) fire beam lasers (`beamweapon=1`). They are now combat-enabled through the native-compared beam host; see BEAM_WEAPONS.md. With them, every armed Core level-one ground unit from the Vehicle Plant and Kbot Lab can fight.

## Evidence

- `native_firing_reference.py --unit <core unit>` and `compare_native_firing.gd` match all snapshots: Thud 322, Leveler 325, Storm 322, Slasher 325, Crasher 323 (1,617 total), including query locals. Summaries: native-thud/leveler/storm/slasher/crasher-firing-validation.json.
- The oracle now skips callbacks a script does not define, as the engine does: Thud and Storm have no `SetMaxReloadTime`. Arm traces are unchanged because every Arm roster script defines all scenario callbacks. Leveler and Slasher define `HitByWeapon`, so their scenarios also exercise hit rocking.
- Slasher's `AimPrimary` starts its own `RequestState` to open the launcher, so no host `Activate` call is needed before firing.
- Real-model muzzle and AimFromPrimary origins with native firing poses now cover the Core five: 1,512 total cases match (native-tank-origin-validation.json). SweetSpot target points with firing poses: 504 total cases match (native-tank-target-validation.json).
- Real Comet Catcher duels: each unit is built by the Core Commander in its original factory, exits, and fights an armed Raider until one is destroyed with both damaged. All five run in the normal verifier (`--verify-corthud` etc.; these flags boot the Core faction). `test_cannon_combat.gd -- --corlevlr` passes 16/16 isolated cannon checks (four directions, raised targets, sounds).

## Thud and Hammer short-range overshoot (resolved: original behavior)

At 128 units the Thud consistently overshoots a Raider. A traced real-map shell crosses the Raider's position about 4 units above its 11.9-unit collision top. Its barrels (`lfirept`/`rfirept`) sit about 5 units above the AimFrom piece (`torso`), and the launch offset compensates only the muzzle's forward (Z) separation. The Arm Hammer has the same geometry.

`native_cannon_launch.py` runs the original executable's complete shot composition on each unit's real model and script:
1. Weapon initialization `0x49e070` at creation pose (heading 32768). Its instructions confirm `trunc((muzzle_z − aim_z) × 1.25)` from the `QueryPrimary` muzzle and AimFrom point.
2. The ballistic aim step of `0x49e1a0`: AimFrom `0x43e2e0`, integer atan `0x4b715a`, aim `0x49a890`. It drives the original `AimPrimary` script for 90 ticks until the turret settles.
3. Turret fire callback `0x49d580`, which `0x49e010` installs as `weapon+0x60` for turret weapons. It re-solves the angles, gates them with tolerance check `0x49d880`, queries the muzzle with `0x43e240`, and launches through `0x49cde0` with the aimed controller heading and pitch.
4. 40 updates of `0x49b720` with collision stubbed.

`compare_native_cannon_launch.gd` replays the same engagements through `combat_world.gd`'s own helpers (`ballistic_angles`, `offset_point`, launch velocity and integration). All 48 engagements match exactly: six cannon units, targets at 128 and 192 units in four directions. Offset, every `AimPrimary` request, muzzle start, launch velocity and all 40 flight positions agree. Summary: native-cannon-launch-validation.json, in `-Native` verification.

Measured in the original's own trajectories, the shell passes the aim point (6 units above ground) at these heights: Thud +4.2 to +5.8, Hammer +4.5 to +9.5, Leveler +1.9 to +4.0, Raider −0.5 to +1.5, Warrior −0.9 to +1.8, Stumpy −1.6 to −3.3. Thud, Hammer and Warrior shells also land up to 8–12 units sideways, because their barrels are offset from the AimFrom piece. So the short-range overshoot is faithful to the original's shot composition. The Thud duel keeps its 192-unit standoff because that is where these faithful shots reach a Raider.

Under the modeled conditions: full health, zero `accuracy` and experience, zero wind drift, a stationary target, and creation heading 32768.

**Firing spread (implemented, native-compared).** `0x49d580` perturbs the absolute launch heading and pitch before the launcher runs:
- **Spread value.** `s = (accuracy − ((signed16 health(unit+0x108) << 11) ÷ maxdamage(def+0x1fa)) + 0x800) & 0xffff`. This equals `accuracy` at full health and grows toward `accuracy + 2048` as health falls.
- **Experience.** Let `d = experience word(unit+0xb8) ÷ 12`; the multiply by `0x2aaaaaab` keeps the ÷6 high word, then `sar 1` halves it. If `d > 1`, `s ÷= d`.
- **Random offsets.** If `s ≠ 0`, heading and then pitch each get `bounded_random(s) − (s >> 1)` from the game RNG `0x4b6c30` (Park–Miller at `0x51fc88`, the same RNG as wind). Bounds below 2 return 0 without a draw.

A first reading of the instructions as ÷6 was wrong. The native comparison exposed it: experience 12 and 17 do not divide, and experience 600 divides by 50.

`combat_world.firing_spread` applies this to every shot from a turret weapon using the shared world game RNG. For ballistic weapons the perturbed angles set launch velocity and burn-blow speed. Direct launchers recompute direction from positions, so there it only consumes the draws, as the original does.

The native oracle adds 10 spread cases per cannon unit on the settled engagement: half health, near-zero health, one hit point lost, accuracy 400, experience 12/17/600, health equal to maximum, 1/1 health, and a wrapping accuracy of 65000 with extreme seeds. The host matches launch heading, pitch, final RNG state, velocity and path in every case (native-cannon-launch-validation.json). `test_firing_spread.gd` pins 10 native-derived fixtures in the normal suite.

Limits: the perturbed controller angles persist into the next tolerance check in the original; the host recomputes aim each tick instead. Non-turret weapon callbacks (`0x49d9c0`, `0x49db70`, `0x49dd60`) are not yet inspected for spread.

## Limits

This checkpoint does not add beam lasers, Core defenses, damage-state script callbacks, wreckage, or AI changes. The opponent still plays Arm. Viewer practice targets can now be spawned for any combat-supported unit, including Core units.
