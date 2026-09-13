# Missile steering

The reconstructed steering primitive matches 624 calls to original function
0x49b520. The native oracle executes the complete function and its angle/distance
helpers with supplied target points; no code inside that function is stubbed.

It calculates desired heading and pitch, then changes each by at most the weapon
record's unsigned 16-bit turn amount at +0xe8. Heading is processed first. With
flag 0x800000, an angular magnitude greater than 27000 rejects steering; pitch
rejection can occur after heading has already changed. A signed 16-bit absolute
magnitude makes the exact half-turn (32768) negative, so the original snaps to
the desired angle even with a small turn allowance. This behavior is preserved.

Cases include random positions, headings/pitches, zero and large turn amounts,
coincident and axis-aligned targets, and explicit turn/rejection/half-turn
boundaries with and without the rejection flag. All outputs (heading, pitch,
and acceptance result) match. The initial comparator falsely rejected equal
values because Godot JSON numbers were floats; explicit integer comparisons
correct that test representation issue.

This is not yet wired into live combat. Target acquisition and leading in
0x49b3e0, loader conversion of turnrate, host flag semantics, tracking lifetime,
and integration with powered flight still need reconstruction. Jethro and Samson
remain unavailable for combat until those pieces are connected and tested.

Reproduce with `python tools/native_missile_steering.py` then Godot headless
`--path godot --script res://compare_native_missile_steering.gd`. The native
verification suite includes this comparison. Native input traces stay local.
