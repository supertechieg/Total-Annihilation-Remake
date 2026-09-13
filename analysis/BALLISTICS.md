# Ballistic motion reconstruction

The live ballistic branch in the original projectile update at `0x0049b720` distinguishes ballistic weapons through bit 1 of weapon offset `0x111`. With zero flight time, it reaches `0x0049bce3`; with a nonzero, unexpired timer it reaches `0x0049bc37`. Both move the shell by its current velocity, add a game-level vector at `GAME+0x37ecc/0x37ed0/0x37ed4`, then subtract gravity at `GAME+0x14263` from vertical velocity. Position and velocity use signed 32-bit fixed-point values and wrap on overflow. The drift vector's derivation remains untraced; it must not yet be assumed to equal a particular wind-speed field.

`ballistic_motion.gd` implements this isolated update. `native_ballistic_reference.py` executes original instructions from `0x0049bb60`, supplying ballistic flags and registers, and replaces the boundary at `0x0049bd86` with return before collision dispatch. No exercised arithmetic is replaced. This is not a full projectile or world simulation oracle.

`compare_native_ballistics.gd` matches 1,120 cases: 1,000 deterministic inputs spanning signed positions/velocities, gravity and drift, both zero and nonzero unexpired flight timers, plus 120 consecutive steps of a shell arc. Five normal regression checks cover update order, input preservation, the arc endpoint, drift and integer wrap. The compact result is `native-ballistic-validation.json`; raw traces stay under ignored `local/ballistics/`.

## Further evidence and unresolved behavior

The map loader uses gravity field `+0xd3c` in its descriptor, and TNT header field 13 for legacy terrain. A zero legacy gravity takes the default raw value `0x1fdb` (8155). Other gravity conversion branches call the original floating-point conversion and still need instruction-level reconstruction. The current ballistic fixture supplies 8155 explicitly; this does not establish the runtime gravity for every map.

Ballistic aiming is at `0x0049a890`, called by the weapon range check at `0x0049aa80`. It consumes relative coordinates, scalar velocity and an angle constraint. Its floating-point intermediates and angle-selection behavior remain to be reconstructed and compared. Ballistic launch at `0x0049cde0` uses the original integer trigonometric helpers and adjusts vertical velocity by a gravity term based on an existing travel accumulator.

The primitive is not connected to Raider world firing yet. Integration still needs verified launch angles/velocity, map gravity and drift, lifetime/expiration rules, terrain and unit collision, and splash damage. The current EMG host's path-length cap is not evidence for ballistic shell lifetime and must not be reused without tracing. Raider retaliation and opponent AI remain outstanding.

Run `python tools/native_ballistic_reference.py`, then Godot `--headless --path godot --script res://compare_native_ballistics.gd`. The normal test is `test_ballistic_motion.gd`; both are included in the appropriate `tools/verify.ps1` modes.
