# First playable Flash combat loop

## Raider cannon and two-way duel

Select a produced Flash and use **Add armed Raider** to spawn an enemy Raider and order both tanks to attack each other. The existing practice target remains passive. This is a development duel control, not autonomous skirmish AI.

Raider firing now uses the compared aim solver, queried muzzle, launch velocity, deadline/expiration and ballistic integration. Shells use map gravity (4369 on Comet Catcher), continue beyond weapon targeting range, and impact through endpoint unit collision or provisional sampled terrain contact. Blasts use half area-of-effect as radius, reconstructed unit boxes, quadratic falloff and damage scaling. The source is excluded; other ground units, including same-owner units, can receive splash. Eight cannon checks verify aiming/firing, rising/falling motion, damage, healthy VM execution and a two-way duel ending in destruction. The full normal suite and existing Comet demos pass.

Remaining integration limits: wind drift is currently zero; splash enumerates live ground records directly rather than reproducing native spatial enumeration and its fixed deduplication limit; features and original effects are absent. Shell aiming still uses the provisional target center. The initialization offset is captured once when the weapon host is first used, before aiming, rather than per shot; exact unit-creation timing and all orientations still need comparison. Current Raider weapontimer is zero; conversion of nonzero timer text in this host is provisional. Terrain contact remains endpoint sampling, and model/world pose limitations remain. The armed Raider holds its assigned target and does not pursue or acquire another one.

Build a Vehicle Plant and produce a Flash. Select the Flash, choose **Add practice target**, then click the red-ringed target. The tank stops, aims, fires EMG bursts, and damages the target until it is removed. Move or Stop cancels the attack; already-launched shots continue. The target is a stationary Core Raider model with its original 1,058 maximum health, not an AI opponent. Practice spawning is a development control, not an original game mechanic.

`combat_world.gd` connects the native-compared firing callbacks and converted weapon values to shot events, projectile movement, collision and health. `piece_origin.gd` now computes the queried muzzle with the native-compared simulation hierarchy arithmetic, replacing the earlier renderer-matrix calculation; see PIECE_ORIGINS.md for72 real-tank query comparisons and remaining host pose limits. Projectile positions and velocity components retain integer16.16 values; render/collision vectors are derived from them. Unit hits use the reconstructed endpoint cell lookup, occupant order and original model-height boundaries (see PROJECTILE_COLLISION.md). Travel is capped at weapon range. Direct damage comes from the weapon definition's unit-name override or default; EMG defaults to8. Shots store the source owner at launch and skip same-owner occupants. The current world team field supplies that owner; alliances remain unimplemented.

Zero-health units are removed from world collections and scene instances. Construction references, factory references, scripts, movement controllers and navigation overlays are cleaned up. The current viewer pauses if its Commander is destroyed and asks for a restart; this is a development policy, not recovered victory-condition logic. No wreckage, salvage, unit death scripts or original destruction explosion runs yet.

The overlay displays temporary line trails, impact circles, enemy rings and health bars. These are development visuals. The original explosion GAFs, effects, audio and team coloring remain to be integrated; the source unit/map artwork is still loaded from local original assets.

## Evidence

Direct hits now use `weapon_damage.gd` for unit-specific base damage and scaling. The isolated calculation matches 600 original-executable cases (see SPLASH_DAMAGE.md). Current world hits use multiplier1, zero experience and no global modifiers. Experience accrual, armor and original health/death dispatch are still absent.

The native prerequisites remain 618 weapon-loader scalar comparisons, 323 Flash firing/query/recoil snapshots, and the earlier movement/COB comparisons. These do not validate the new world combat rules.

19 combat host checks cover supported/enemy orders, aim gating, projectile hits, health reduction, VM faults, stop, range gating, destruction/order cleanup, endpoint collisions, owner filtering, model-height misses, intervening-unit skips, fixed-point integration, projectile expiration and destroyed construction cleanup. Normal regression checks pass. A real Comet Catcher integration builds the factory, produces two Flash tanks, selects one, spawns/attacks a target and verifies destruction and scene removal. A live rendered capture was inspected.

Run `tools/verify.ps1` for the full normal suite, including `--verify-combat`. Use Godot `--path godot -- --combat-demo --capture ABSOLUTE_PNG_PATH` for a live firing capture.

## Fidelity limits and next work

Only Flash primary EMG firing is connected. There is no autonomous target acquisition, pursuit, firing while moving, enemy retaliation or opponent economy. Targets are aimed at a provisional center 12 units above sampled terrain. Ground hits now use the live reconstructed occupancy grid and original model heights. Air/naval slot classification, overlap recovery, feature/terrain intersection and slope/altitude remain incomplete. Terrain currently removes shots when their endpoint falls below sampled terrain.

Direction vectors use floating-point geometry before integer projectile integration; unit collision uses fixed-point endpoints and bounds. Native normalization/rounding, EMG spray/random state, target leading, splash/edge effectiveness, armor and damage modifiers are not reconstructed. Shots currently point at the target center without applying EMG spray. Health reads supplied to healthy COB scripts remain 100; damaged smoke, HitByWeapon, Killed and other damage callbacks await world integration. The practice target now executes its native-compared healthy Core Raider script, but has no AI or ballistic weapon host yet. See FIRING_CYCLE.md for the Raider's 325-snapshot callback comparison.

The firing controller's countdown and aim-refresh policy remain provisional. EMG has no per-shot metal/energy cost; costed weapons need additional accounting. Movement, placement, resource settlement and yard rules retain their previously documented limitations. Next work must expand and compare these behaviors, add opponents and the other weapons/factions, and continue toward missions and the remaining complete-game systems. This is a first playable combat checkpoint, not completion of the faithful recreation.
