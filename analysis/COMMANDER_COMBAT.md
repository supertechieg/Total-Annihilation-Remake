# Commander combat

Both Commanders now fight with their primary beam lasers: Arm J7 Laser (ARMCOMLASER: range 200, damage 60, reload 25 ticks) and Core XC Laser (CORCOMLASER: range 200, damage 70, reload 30 ticks). Both use the native-compared beam host (BEAM_WEAPONS.md), spread (CORE_COMBAT.md) and terrain collision (PROJECTILE_COLLISION.md).

## Evidence

- **Firing scripts.** `native_firing_reference.py --unit armcom|corcom` with `compare_native_firing.gd` match 322/322 snapshots for each Commander (Create, AimPrimary, QueryPrimary/FirePrimary overlap). The primary muzzle query returns piece 6 for Arm and piece 1 for Core. Summaries: native-arm-commander-firing-validation.json and native-core-commander-firing-validation.json. Walking and building were already covered by the 464-snapshot Commander comparisons.
- **Integration.** The Commander's script and movement controller belong to the viewer, which steps them. `ConstructionWorld.attach_external` registers them in the world so combat, SweetSpot targeting, orders and the weapon launch offset can use them, while the world skips stepping them.
- **Holding guard.** `CombatWorld.enable_guard(id, false)` acquires only within the lesser of sight distance and weapon range, and never stops or moves the unit, so the player keeps control of the Commander's movement. A player-issued pursuit attack is left in place.
- **Orders.** Clicking an enemy with the Commander selected issues a pursuit attack. Move and Stop orders cancel Commander attacks.
- **Tests.** `test_commander_combat.gd` passes 24 checks for both Commanders: holding fire and damage without movement, no engagement beyond weapon range, pursuit that closes distance and damages, launch-offset capture, a fault-free script, and enemies damaging the Commander through its SweetSpot. `--verify-commander-combat` on Comet Catcher (also `--faction core`) spawns an enemy 160 units away, which each Commander destroys in place. All run in NORMAL verification; the Commander firing oracles run under `-Native`.

## D-gun (Disintegrator)

Weapon 3 on both Commanders is a command-fire (`commandfire=1`) beam: range 240, speed 200, area of effect 48, 30,000 damage, 400 energy per shot, `noexplode`.

Recovered original behavior:
- **Fire callback.** Turret weapons of every slot use fire callback `0x49d580`, which calls `Aim/Query/FireTertiary` for slot 3.
- **Energy.** `0x49e1a0` fires a non-stockpile weapon only when the owner's stock covers `energypershot` (`weapon+0xc0`) and `metalpershot` (`+0xc4`). After a shot, `0x4012a0` subtracts the cost from stock immediately and adds it to the unit's requested energy and metal. It does not go through deferred settlement.
- **No-explode.** Impact dispatch `0x499eb0` removes the projectile only when `noexplode` (`0x400000`) is clear. With area of effect 17 or more, unit hits take the splash path `0x49a120`; below 17 they take direct damage. Terrain impacts also splash. A D-gun therefore keeps flying and splashes every tick it touches a unit cell or terrain until its range-derived deadline.

Implementation:
- **Weapon slots.** `WeaponCycle` and `WeaponQueries` take a slot name. Only the primary cycle sends `SetMaxReloadTime`.
- **Command fire.** `CombatWorld.command_fire(source, target)` runs a separate slot-3 cycle, pursues into range, fires once, then completes. It takes movement control from any primary attack.
- **Energy and impacts.** Every weapon now checks and pays per-shot energy and metal (zero for all other supported weapons). Beam impacts follow the area-of-effect split and `noexplode` rule above.
- **Viewer.** The `D` key or the **D-gun target** button, then clicking an enemy, issues the order.

Evidence:
- **Scripts.** The Commander firing oracle adds `AimTertiary` at tick 200 and `QueryTertiary`/`FireTertiary` at 230/233. Both Commanders match 327/327 snapshots, with tertiary muzzle piece 3 for Arm and 2 for Core.
- **Tests.** `test_dgun.gd` passes 21 checks. For both Commanders, one command shot at the first of three enemies lined up 110–190 units away destroys all three. Exactly one shot is fired, 400 energy is taken from stock and added to requested on that tick, the order completes, and the Commander and its script stay healthy. A D-gun order with only 100 energy never fires, and units without a command-fire weapon are rejected.
- **Real map.** `--verify-dgun` on Comet Catcher (and `--faction core`) destroys three enemies with one shot. Energy drops from 1,000 to about 625 including income.
- **A bug the test caught.** Completing the command order stopped its cycle, which cleared the pending shot list before projectiles were created. The host now copies emitted shots first.

## Limits

- **D-gun targeting.** Ground-point targeting is not implemented; the D-gun needs a unit target. The flying ball is drawn as a development beam line. Stockpile weapons are not implemented.
- **Splash scope.** The area-of-effect and terrain-splash dispatch rule is applied to beams. Direct E.M.G. rounds keep their previous terrain handling.
- **Guard policy.** Target choice is the host's nearest-enemy rule, not recovered original fire-at-will scanning. The host also fires only when the unit is stopped.
- **Building.** Whether the original lets a Commander fire while building is left to its script and the host's stationary rule; interruptions are not yet native-compared.
