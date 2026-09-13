# Rocket and missile flight work

Rocko's KBOT_ROCKET uses line-of-sight/self-propelled flight, start velocity 250,
maximum velocity 250 and acceleration 120. Jethro and Samson add guidance/tracking
and start below their maximum speed. None is enabled for combat yet.

The direct launch helper now implements the original initial-speed selection:
use a nonzero start speed; otherwise start at zero if acceleration is nonzero;
otherwise use maximum speed. It does not clamp a supplied start speed to maximum
at launch. Native `0x49ca37..0x49cb1c` comparison passes 240 cases spanning these
branches, including start speed above maximum, three maximum speeds, arbitrary
coordinates and axis/coincident cases. Heading, pitch, distance, chosen speed
and resulting velocity all match. Default arguments preserve existing EMG behavior.

Next reconstruct the self-propelled update path, prepare native-compared start
velocity/acceleration scalars, then verify Rocko's firing script and a live duel.
Guided steering, missile presentation, smoke and original impact effects remain
separate unfinished work. These launch checks do not establish flight fidelity.

## Unguided powered-flight update

`rocket_motion.gd` now matches 240 native `0x49b720` cases with self-propelled and
line-of-sight flags. Before the unsigned deadline, speed increases toward maximum
and velocity is rebuilt from heading/pitch using the integer trig table. A speed
already above maximum is retained. At or after the deadline, the rocket keeps its
horizontal velocity, subtracts gravity from vertical velocity, then moves. It does
not simply expire like an EMG round.

Cases cover zero/partial/maximum/above-maximum speeds, three acceleration values,
three gravity values, arbitrary angles and deadline boundaries. Collision and
pool consolidation are stubbed; guidance, water, smoke, burnblow and cruise are
excluded. This primitive is not yet connected to live combat. Start-speed and
acceleration scalar preparation and Rocko firing verification remain next.

Reproduce with `python tools/native_rocket_motion.py`, then Godot headless with
`--path godot --script res://compare_native_rocket_motion.gd`.
