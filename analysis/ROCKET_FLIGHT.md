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
