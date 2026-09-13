# Ballistic motion reconstruction

The live ballistic branch in the original projectile update at `0x0049b720` distinguishes ballistic weapons through bit 1 of weapon offset `0x111`. With zero flight time, it reaches `0x0049bce3`; with a nonzero, unexpired timer it reaches `0x0049bc37`. Both move the shell by its current velocity, add a game-level vector at `GAME+0x37ecc/0x37ed0/0x37ed4`, then subtract gravity at `GAME+0x14263` from vertical velocity. Position and velocity use signed 32-bit fixed-point values and wrap on overflow. The drift vector's derivation remains untraced; it must not yet be assumed to equal a particular wind-speed field.

`ballistic_motion.gd` implements this isolated update. `native_ballistic_reference.py` executes original instructions from `0x0049bb60`, supplying ballistic flags and registers, and replaces the boundary at `0x0049bd86` with return before collision dispatch. No exercised arithmetic is replaced. This is not a full projectile or world simulation oracle.

`compare_native_ballistics.gd` matches 1,120 cases: 1,000 deterministic inputs spanning signed positions/velocities, gravity and drift, both zero and nonzero unexpired flight timers, plus 120 consecutive steps of a shell arc. Five normal regression checks cover update order, input preservation, the arc endpoint, drift and integer wrap. The compact result is `native-ballistic-validation.json`; raw traces stay under ignored `local/ballistics/`.

## Further evidence and unresolved behavior

The map loader uses gravity field `+0xd3c` in its descriptor, and TNT header field 13 for legacy terrain. A zero legacy gravity takes the default raw value `0x1fdb` (8155). Other gravity conversion branches call the original floating-point conversion and still need instruction-level reconstruction. The current ballistic fixture supplies 8155 explicitly; this does not establish the runtime gravity for every map.

Ballistic aiming is at `0x0049a890`, called by the weapon range check at `0x0049aa80`. `ballistic_aim.gd` now reconstructs its two candidate angles from source-minus-target fixed-point coordinates, velocity, supplied gravity and minimum angle. The routine selects the first acceptable candidate, requiring it to exceed the minimum and not exceed the executable's approximately pi/4 constant. Failure is the low-word sentinel `0x8000`; callers must not interpret it as a firing angle. Its conversion uses the executable's binary64 constants 32768 and 0.318309886183791 before truncation.

`native_ballistic_aim.py` executes the complete unmodified aim routine and original CRT math. The Godot reconstruction matches all 1,236 cases: 1,200 deterministic varied inputs and 36 boundary inputs covering zero/tiny horizontal distances, higher/lower targets, minimum-angle rejection and adjacent fixed-point distances across maximum reach. There are 494 accepted cases. Nine fixed native examples run in normal verification. The compact report is `native-ballistic-aim-validation.json`. These comparisons cover positive speed and gravity up to 16000; Godot uses binary64 intermediates instead of a general x87 emulator, so untested precision boundaries and abnormal inputs remain unproven.

Ballistic launch at `0x0049cde0` still needs reconstruction: it uses the original integer trigonometric helpers and adjusts vertical velocity by a gravity term based on an existing travel accumulator. The source and host evolution of the minimum-angle constraint also remain untraced.

The primitive is not connected to Raider world firing yet. Integration still needs verified launch angles/velocity, map gravity and drift, lifetime/expiration rules, terrain and unit collision, and splash damage. The current EMG host's path-length cap is not evidence for ballistic shell lifetime and must not be reused without tracing. Raider retaliation and opponent AI remain outstanding.

Run `python tools/native_ballistic_reference.py`, then Godot `--headless --path godot --script res://compare_native_ballistics.gd`. The normal test is `test_ballistic_motion.gd`; both are included in the appropriate `tools/verify.ps1` modes.
