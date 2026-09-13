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
excluded. This primitive is not yet connected to live combat. Rocko firing verification and live rocket integration remain next.

Reproduce with `python tools/native_rocket_motion.py`, then Godot headless with
`--path godot --script res://compare_native_rocket_motion.gd`.


## Prepared start speed and acceleration

Weapon runtime schema 3 includes start_velocity_raw_per_tick and
acceleration_raw_per_tick_squared. The original loader at 0x42e4e4 scales start
speed by binary64 65536/30; at 0x42e502 it scales acceleration by binary64
65536/900. Both truncate the x87 product and store a 32-bit result.
The expanded native comparison passes 1,233 cases across the bundled weapon
fields and supplied boundaries. This includes the shipped acceleration text
`13O`, whose numeric prefix is read as 13 by the original parser. Python tests
cover that case, and the regenerated Godot catalog passes 8,925 checks.
This verifies numeric fields, not a complete recreation of the original text
parser or live rocket combat.


## Rocko firing and model queries

Rocko's healthy firing script matches 323 snapshots from the original interpreter
at supplied Create, AimPrimary, QueryPrimary and FirePrimary callback times.
All nine QueryPrimary calls return piece 1. This verifies script execution under
the supplied events, not the original host's firing cadence.

Adding Rocko firing poses to the shared model fixtures yields 648 matching
muzzle/AimFrom cases and 216 matching SweetSpot cases across six units and four
headings. Original axis conversion, pose setters and traversal run in the oracle;
full model loading, damaged scripts and walking-to-firing transitions remain
outside these checks. Live rocket combat remains to be connected.

Reproduce with `python tools/native_firing_reference.py --unit armrock` and Godot
`--headless --path godot --script res://compare_native_firing.gd -- --armrock`.
The native verification suite includes this comparison.


## Live Rocko combat

Rocko now participates in attack orders and guard combat. Its direct launch uses
prepared start speed and acceleration; each flight tick runs the native-compared
unguided rocket motion. On the 48-tick range-derived motor deadline it begins falling under map
gravity. Endpoint unit/terrain impacts use shared splash damage. The supported
rocket is KBOT_ROCKET only: guided missiles, cruise, burnblow, water transitions,
smoke trails, original explosion art/audio and full host timing remain unfinished.
The current nonballistic script aim pitch remains zero, while actual projectile
heading/pitch are calculated from muzzle to target; script elevation fidelity
still needs investigation.

The 17-check rocket combat test covers shots, damage, an armed duel, four firing
directions, elevated targets and survival/fall at the motor deadline. The viewer
`--verify-rocko` builds an Arm Kbot Lab, produces and moves a Rocko, then verifies
that it and an armed Raider exchange damage and one is destroyed on Comet Catcher.
Both are included in the normal verification suite. Practice-target controls
accept a selected Rocko. Projectile visuals remain the existing simple trails.


## Corrected launch deadline

Native direct-launch block 0x49cb1c..0x49cb61 passes 240 cases. With nonzero
maximum speed and noautorange clear, duration is unsigned
((range << 16) & 0xffffffff) / maximum speed, truncated to an integer. Otherwise
it uses the unsigned 16-bit weapon timer. Tick addition wraps to 32 bits.
Loader string references identify +0xdc as range and flag 0x08000000 as
noautorange. Rocko therefore powers for 48 ticks, not 60. Live combat now uses
this calculation. The rocket test checks the emitted deadline and still passes
all 17 checks; the factory-produced Comet Catcher duel also passes.
