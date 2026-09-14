# Commander combat

Both Commanders now fight with their primary beam lasers: Arm J7 Laser (ARMCOMLASER: range 200, damage 60, reload 25 ticks) and Core XC Laser (CORCOMLASER: range 200, damage 70, reload 30 ticks). Both use the native-compared beam host (BEAM_WEAPONS.md), spread (CORE_COMBAT.md) and terrain collision (PROJECTILE_COLLISION.md).

## Evidence

- **Firing scripts.** `native_firing_reference.py --unit armcom|corcom` with `compare_native_firing.gd` match 322/322 snapshots for each Commander (Create, AimPrimary, QueryPrimary/FirePrimary overlap). The primary muzzle query returns piece 6 for Arm and piece 1 for Core. Summaries: native-arm-commander-firing-validation.json and native-core-commander-firing-validation.json. Walking and building were already covered by the 464-snapshot Commander comparisons.
- **Integration.** The Commander's script and movement controller belong to the viewer, which steps them. `ConstructionWorld.attach_external` registers them in the world so combat, SweetSpot targeting, orders and the weapon launch offset can use them, while the world skips stepping them.
- **Holding guard.** `CombatWorld.enable_guard(id, false)` acquires only within the lesser of sight distance and weapon range, and never stops or moves the unit, so the player keeps control of the Commander's movement. A player-issued pursuit attack is left in place.
- **Orders.** Clicking an enemy with the Commander selected issues a pursuit attack. Move and Stop orders cancel Commander attacks.
- **Tests.** `test_commander_combat.gd` passes 24 checks for both Commanders: holding fire and damage without movement, no engagement beyond weapon range, pursuit that closes distance and damages, launch-offset capture, a fault-free script, and enemies damaging the Commander through its SweetSpot. `--verify-commander-combat` on Comet Catcher (also `--faction core`) spawns an enemy 160 units away, which each Commander destroys in place. All run in NORMAL verification; the Commander firing oracles run under `-Native`.

## Limits

- **D-gun.** The Disintegrator (weapon 3: command fire, 400 energy per shot, `noexplode`, 30,000 damage) is not connected. Command fire, per-shot energy cost and non-exploding beams through units are separate work.
- **Guard policy.** Target choice is the host's nearest-enemy rule, not recovered original fire-at-will scanning. The host also fires only when the unit is stopped.
- **Building.** Whether the original lets a Commander fire while building is left to its script and the host's stationary rule; interruptions are not yet native-compared.
