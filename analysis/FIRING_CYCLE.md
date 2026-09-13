# Flash firing callback and burst-controller prerequisite

`native_firing_reference.py` runs the original Flash COB with healthy host input, SetMaxReloadTime, supplied aim angles, and nine QueryPrimary/FirePrimary pairs across three supplied three-shot groups. It compares query output locals as well as piece transforms, recoil targets/velocities, visibility, statics, threads and other VM state. All 323 snapshots match through `compare_native_firing.gd`; the compact result is native-firing-validation.json.

The muzzle query sequence for the first group is 0, 0, 1. QueryPrimary returns the current muzzle static, and FirePrimary toggles that static later in its timed execution. Overlapping callbacks therefore do not simply alternate barrels once per host shot. The original script is the authority for muzzle selection. These callback times are supplied test inputs, not evidence for the original weapon scheduler's burst cadence.

`weapon_cycle.gd` is a scene-independent primary-weapon controller intended for the upcoming projectile host. The caller advances the VM before the controller each tick, supplies aiming angles and firing permission, and consumes emitted shot records. It waits for a successful AimPrimary return, reads the muzzle through QueryPrimary's output local, invokes FirePrimary, and emits the queried piece name/index with the converted weapon velocity. It forwards converted maximum reload time to SetMaxReloadTime.

The current EMG host emits three shots separated by the converted three-tick burst interval, with a twelve-tick reload counted from burst start. It refreshes aim after a burst and after firing permission recovers, so the original idle-restoration callback cannot leave it firing from a restored turret pose. Stopping cancels future shots while allowing existing recoil callbacks to finish. Replacing the aim request observes only the latest invocation's result.

Fourteen host checks cover aiming readiness, two bursts, turret orientation, intervals, native-compared barrel selection, converted velocity, stopping, permission gating/recovery, replacement aim, sustained firing and VM faults. These establish the stated provisional host policy. Original countdown order, reload origin, repeated aim scheduling, burst defaults/zero intervals, shot costs, targeting/range checks and behavior for other weapon types still need native world comparison.

The controller is not yet connected to the playable world. Projectile spawn transforms, spread/random state, collision, damage, destruction and opponents are still required. No new combat capability is claimed for the viewer by this checkpoint. The complete-game objective remains active.

Normal checks run via `tools/verify.ps1`; `-Native` includes the original Flash comparison.
