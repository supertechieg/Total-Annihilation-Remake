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


## Prepared turn allowance

Weapon runtime schema 4 adds turn_raw_per_tick. Original loader instructions
0x42e60e through 0x42e619 multiply parsed turnrate by the binary64 constant
1/30, truncate the x87 product and store its low 16 bits at weapon +0xe8.
Samson's 30000 becomes 999; Jethro's 33000 becomes 1099. Boundary value 30
becomes zero, demonstrating why ordinary rounding or integer division changes
behavior. The scalar oracle now covers turnrate in every bundled definition
and supplied fractional boundaries. Steering remains separate from live combat.


## Ordinary target point selection

Full original function 0x49b3e0, with cruise flag 0x02000000 clear, selects:

1. The referenced projectile's position (+4) when projectile +0x56 is nonzero.
2. The referenced unit's position (+0x6a) when projectile +0x4e is nonzero and
   that unit has flag 0x10000000 at +0x110.
3. The projectile's saved point (+0x28) otherwise.

It performs no SweetSpot query or target leading in this branch. The pure
selection helper matches 48 native calls over changing point coordinates,
competing references, absent references and valid/invalid units. The oracle
executes the full function without stubs; cruise branches are not exercised.

This does not yet establish target-reference assignment, destruction cleanup,
or when saved points are refreshed. It must not be interpreted as proof of
complete target-loss behavior. The native verification suite runs the new
native_missile_target.py and compare_native_missile_target.gd comparison.


## Combined ordinary guided flight

The composed guided_motion helper matches 240 executions of the full original
0x49b720 updater with weapon flags 0x101001 (ordinary self-propelled guidance),
steering toward saved points. Native 0x49b3e0 target selection and 0x49b520
steering execute without stubs. Collision and pool consolidation are isolated.
Checks compare heading, pitch, speed, velocity and position before, at and after
the deadline, across zero/partial/maximum/above-maximum speeds, varying gravity,
acceleration, target points and turn allowances including Samson/Jethro values.

The original accelerates, steers and recomputes velocity before moving during
powered flight. Acceleration and steering are independent for this ordinary
branch, allowing the helper to compose existing primitives. At the deadline,
steering stops and gravity changes vertical velocity while angles remain stored.
Burnblow flag 0x800000 instead calls the impact handler, including when steering
rejects a turn. Vertical-launch flag 0x1000000 has further state transitions.
Those special modes, cruise, water, referenced-target assignment/cleanup and
live guided combat remain outside this helper. No additional combat unit is
enabled by this checkpoint.

Reproduce using native_guided_motion.py and compare_native_guided_motion.gd;
both are included in the native verification suite.


## Samson and Jethro firing scripts

The native supplied-event firing fixture now includes armsam and armjeth. Each
matches all 323 original-interpreter snapshots, including piece transformations,
visibility, threads, static variables and synchronous QueryPrimary output.
Jethro returns pieces 1,2,1,2,1,2,1,2,1 for the nine supplied query/fire pairs;
Samson returns 0,0,1,1,1,0,0,0,1. No VM changes were needed. Their weapon data
confirms ordinary selfprop/guidance/tracks with five-second timers and no cruise,
vertical-launch or burnblow field in the prepared definitions.

These checks use healthy scripts with supplied callback timing. They do not prove
native host firing cadence, moving/air targets, damaged script behavior or live
missile combat. Native real-model muzzle comparisons for these two units and
live integration remain outstanding. The native suite now runs both firing
comparisons; full traces and original script data remain excluded from Git.
