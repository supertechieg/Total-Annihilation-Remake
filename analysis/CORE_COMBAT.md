# Core level-one combat roster

The Core Thud (`corthud`), Leveler (`corlevlr`), Storm (`corstorm`), Slasher (`cormist`) and Crasher (`corcrash`) now fight with the existing cannon, rocket and guided-missile hosts, alongside the Raider that was already supported. Their weapons match Arm counterparts in class: Thud's plasma cannon is the Hammer's class (speed 210, minbarrelangle -35), Leveler's is a ballistic light cannon (speed 280, AoE 84), Storm fires self-propelled unguided rockets like Rocko, and Slasher/Crasher fire guided tracking missiles like Samson/Jethro. Combat reads everything from each unit's `weapon1` definition; no Core-specific combat logic was added.

The three Core laser units (Instigator `corgator`, Weasel `corfav`, A.K. `corak`) and Arm's Jeffy (`armfav`) fire beam lasers (`beamweapon=1`). They are now combat-enabled through the native-compared beam host; see BEAM_WEAPONS.md. With them, every armed Core level-one ground unit from the Vehicle Plant and Kbot Lab can fight.

## Evidence

- `native_firing_reference.py --unit <core unit>` and `compare_native_firing.gd` match all snapshots: Thud 322, Leveler 325, Storm 322, Slasher 325, Crasher 323 (1,617 total), including query locals. Summaries: native-thud/leveler/storm/slasher/crasher-firing-validation.json.
- The oracle now skips callbacks a script does not define, as the engine does: Thud and Storm have no `SetMaxReloadTime`. Arm traces are unchanged because every Arm roster script defines all scenario callbacks. Leveler and Slasher define `HitByWeapon`, so their scenarios also exercise hit rocking.
- Slasher's `AimPrimary` starts its own `RequestState` to open the launcher, so no host `Activate` call is needed before firing.
- Real-model muzzle and AimFromPrimary origins with native firing poses now cover the Core five: 1,512 total cases match (native-tank-origin-validation.json). SweetSpot target points with firing poses: 504 total cases match (native-tank-target-validation.json).
- Real Comet Catcher duels: each unit is built by the Core Commander in its original factory, exits, and fights an armed Raider until one is destroyed with both damaged. All five run in the normal verifier (`--verify-corthud` etc.; these flags boot the Core faction). `test_cannon_combat.gd -- --corlevlr` passes 16/16 isolated cannon checks (four directions, raised targets, sounds).

## Thud short-range overshoot (open)

At 128 units the Thud consistently overshoots a Raider. A traced real-map shell crosses the Raider's position at height 71 over ground 55, about 4 units above the Raider's 11.9-unit collision top, and lands 81 units beyond it. The aim solver is not at fault: it returns 43 (0.24°), matching a physics estimate from the AimFrom point. The Thud's barrels (`lfirept`/`rfirept`) sit about 5 units above its AimFrom piece (`torso`). The native launch offset compensates only the muzzle's forward (Z) separation, so shells start high and stay high at short range. On flat ground the isolated cannon test shows the same pattern: 13/16, missing a Flash to the north at 128 and a 24-unit raised target.

The Arm Hammer shares this geometry. A flat-ground probe showed it also overshooting a Flash at 128, and HAMMER_COMBAT.md already records one Hammer barrel overshooting in its duel. Every component in the chain individually matches the original executable, so this may be faithful original behavior or an unreconstructed integration detail: target leading from `0x48a1e0`, controller state updates after `0x49e070`, or collision sampling. The Thud duel therefore uses a 192-unit standoff, where descending shells enter the Raider's box. This is not a claim that short-range Thud accuracy matches the original.

## Limits

This checkpoint does not add beam lasers, Core defenses, damage-state script callbacks, wreckage, or AI changes. The opponent still plays Arm. Viewer practice targets can now be spawned for any combat-supported unit, including Core units.
