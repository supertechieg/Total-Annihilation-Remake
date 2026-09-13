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

This primitive is not yet connected to combat. The SweetSpot script host behavior
and real-model adapter still need verification.
Raw prepared model vertices are not a verified substitute. Combat currently
targets the unit position plus half its static blast-bound height.

Reproduce with `python tools/native_target_point.py`, then run Godot headless
with `--path godot --script res://compare_native_target_point.gd`.
The optional native verification suite includes both steps. Raw traces remain
under ignored `local/target-point`; only the comparison summary is committed.

## Runtime vertex transformation

`0x45ab10` updates a dirty unit model. It copies original geometry vertices into
runtime arrays, then invokes `0x45b0a0` and `0x45b150` to transform the tree.
Each vertex is rotated by its own piece, translated by that piece's offset and
script movement, then similarly transformed through its ancestors. Root rotation
adds unit pitch to piece X, heading to Y and roll to Z. Unlike the firing-origin
routine, this vertex path does not perform a final Z negation.

`TargetPoint.transform_vertex` matches all 1,752 vertices in 300 synthetic trees
against the complete original `0x45ab10` routine without replacing its callees.
Trees contain up to seven pieces, branching siblings, empty pieces and arbitrary
rotations and translations. This verifies dirty recomputation, not cache behavior.
The original refreshes cached unit angles when a signed angle difference exceeds
seven; that update threshold is not implemented here.

Reproduce with `python tools/native_target_vertices.py` and Godot script
`res://compare_native_target_vertices.gd`. Both are in the optional native suite.
Original geometry must still undergo the loader's X/Z inversion before use.
