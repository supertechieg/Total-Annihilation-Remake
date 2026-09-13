# First playable Flash combat loop

Build a Vehicle Plant and produce a Flash. Select the Flash, choose **Add practice target**, then click the red-ringed target. The tank stops, aims, fires EMG bursts, and damages the target until it is removed. Move or Stop cancels the attack; already-launched shots continue. The target is a stationary Core Raider model with its original 1,058 maximum health, not an AI opponent. Practice spawning is a development control, not an original game mechanic.

`combat_world.gd` connects the native-compared firing callbacks and converted weapon values to shot events, projectile movement, collision and health. `piece_origin.gd` now computes the queried muzzle with the native-compared simulation hierarchy arithmetic, replacing the earlier renderer-matrix calculation; see PIECE_ORIGINS.md for72 real-tank query comparisons and remaining host pose limits. Projectile positions and velocity components retain integer16.16 values; render/collision vectors are derived from them. Swept segment tests choose the nearest intersected unit rather than testing only projectile endpoints. Travel is capped at weapon range. Direct damage comes from the weapon definition's unit-name override or default; EMG defaults to8. Friendly units can intercept projectiles even though explicit friendly attack orders are rejected.

Zero-health units are removed from world collections and scene instances. Construction references, factory references, scripts, movement controllers and navigation overlays are cleaned up. The current viewer pauses if its Commander is destroyed and asks for a restart; this is a development policy, not recovered victory-condition logic. No wreckage, salvage, unit death scripts or original destruction explosion runs yet.

The overlay displays temporary line trails, impact circles, enemy rings and health bars. These are development visuals. The original explosion GAFs, effects, audio and team coloring remain to be integrated; the source unit/map artwork is still loaded from local original assets.

## Evidence

The native prerequisites remain 618 weapon-loader scalar comparisons, 323 Flash firing/query/recoil snapshots, and the earlier movement/COB comparisons. These do not validate the new world combat rules.

18 combat host checks cover supported/enemy orders, aim gating, projectile hits, health reduction, VM faults, stop, range gating, destruction/order cleanup, swept collision and near misses, nearest-hit ordering, fixed-point integration, projectile expiration and destroyed construction cleanup. Normal regression checks pass. A real Comet Catcher integration builds the factory, produces two Flash tanks, selects one, spawns/attacks a target and verifies destruction and scene removal. A live rendered capture was inspected.

Run `tools/verify.ps1` for the full normal suite, including `--verify-combat`. Use Godot `--path godot -- --combat-demo --capture ABSOLUTE_PNG_PATH` for a live firing capture.

## Fidelity limits and next work

Only Flash primary EMG firing is connected. There is no autonomous target acquisition, pursuit, firing while moving, enemy retaliation or opponent economy. Targets are aimed at a provisional center 12 units above sampled terrain. Unit hit volumes use footprint-derived spheres; native collision shapes, feature/terrain intersection, slope/altitude and exact muzzle/world projection remain unverified. Terrain currently removes shots when their endpoint falls below sampled terrain.

Direction vectors and collision tests use floating-point geometry before/around integer projectile integration. Native normalization/rounding, EMG spray/random state, target leading, splash/edge effectiveness, armor and damage modifiers are not reconstructed. Shots currently point at the target center without applying EMG spray. Health reads supplied to healthy COB scripts remain 100; damaged smoke, HitByWeapon, Killed and other damage callbacks await world integration. The practice target now executes its native-compared healthy Core Raider script, but has no AI or ballistic weapon host yet. See FIRING_CYCLE.md for the Raider's 325-snapshot callback comparison.

The firing controller's countdown and aim-refresh policy remain provisional. EMG has no per-shot metal/energy cost; costed weapons need additional accounting. Movement, placement, resource settlement and yard rules retain their previously documented limitations. Next work must expand and compare these behaviors, add opponents and the other weapons/factions, and continue toward missions and the remaining complete-game systems. This is a first playable combat checkpoint, not completion of the faithful recreation.
