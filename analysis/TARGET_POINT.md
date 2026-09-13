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

Combat now uses the model adapter and synchronous SweetSpot query for all targets
with a usable script and model. Invalid queries retain a half-height fallback. The adapter
converts prepared vertices and offsets through the original loader convention.

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

## Real tank integration

108 cases compare Flash, Raider and Stumpy using recorded native firing poses,
script statics, four headings and a nonzero world position. The oracle executes
original axis conversion `0x4cb590`, full model update `0x45ab10` and SweetSpot
wrapper `0x43e3c0`, including the original script interpreter. All match the Godot
adapter. Runtime records are arranged by script piece names; the full original
model loader and its allocation/reordering remain outside this test.

Live combat uses these points for horizontal aiming, cannon elevation, projectile
direction and burn-blow distance. Target vertices are recomputed from current
poses; original angle-cache thresholds and refresh scheduling remain unmodeled.
This does not establish original leading behavior or fidelity for other units.
The normal verification suite, including Flash and Stumpy duels, passes.

Reproduce with `python tools/native_tank_targets.py` and Godot script
`res://compare_native_tank_targets.gd` after generating the native firing traces.

## Full roster baseline

The `--roster` option on both tools checks all 272 prepared units at four headings,
zero script pose and a translated world position. All 1,088 cases match the original
axis conversion, model update and SweetSpot wrapper. 252 scripts define SweetSpot;
20 use the default piece index. Arm/Core Dragon's Teeth and Core Fortification
have no script pieces, so runtime name ordering must append model pieces before
resolving that default. Combat now handles this case and enables model target
points throughout the roster.

This baseline does not execute Create or validate every unit's animated states.
Only the three tank tests above cover recorded firing poses and statics. Flight
altitude, unit roll/pitch, cache scheduling and target leading remain outside the
current combat host's fidelity. The full normal verification suite passes after
enabling the roster adapter.
