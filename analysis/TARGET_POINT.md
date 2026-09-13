# Original unit target point

The reconstructed `target_point.gd` implements original function `0x43e0b0`.
The native comparison passes 600 cases, including empty geometry, signed limits,
odd negative midpoint rounding, position overflow and seven runtime piece indices.
The oracle executes the complete original routine without callback substitutions.

The routine reads the selected piece record at `model + 0x22 + index * 0x36`.
Its geometry pointer supplies the vertex count at offset 4, but the vertex array
comes from runtime record offset `0x22`, not the original geometry vertex pointer.
For each axis, minimum and maximum start at zero, so the bounds include the origin.
It halves their signed sum with truncation toward zero, adds unit position and
preserves signed 32-bit wrapping.

Original wrapper `0x43e3c0` initializes the piece index to zero and invokes the
unit's `SweetSpot` script before calling this routine. Unit-target resolution
`0x48a1e0` calls that wrapper. Target leading is a separate behavior.

This primitive is not yet connected to combat. The producer of the runtime
transformed vertices and the SweetSpot script host behavior still need tracing.
Raw prepared model vertices are not a verified substitute. Combat currently
targets the unit position plus half its static blast-bound height.

Reproduce with `python tools/native_target_point.py`, then run Godot headless
with `--path godot --script res://compare_native_target_point.gd`.
The optional native verification suite includes both steps. Raw traces remain
under ignored `local/target-point`; only the comparison summary is committed.
