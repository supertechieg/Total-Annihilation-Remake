# Initial opponent controller

opponent.gd is a provisional skirmish policy, not a reconstruction of original TA
AI. Once per second it queues a Flash or Peewee in idle owned factories, using
normal construction costs and scripts. Completed supported combat units finish
factory exit movement, choose the nearest enemy and use normal attack pursuit.
Queues remain bounded to one pending unit per factory. Existing attack orders
are retained while targets exist; destroyed factories stop production requests.

The test_opponent.gd integration test starts a funded enemy factory on flat
terrain, requires resource spending, factory-produced enemy ownership, an attack
and actual damage to a player target, then removes the factory and checks that
queuing stops. All eight checks pass. It is included in normal verification.

The controller is not yet attached to a viewer scenario. It starts from a supplied
factory, has full-world target knowledge and lacks base construction, scouting,
fog-of-war, strategic unit composition, resource expansion and mission behavior.
These remain required toward a complete game; the test is a production-to-combat
milestone only.


## Initial base construction

The policy now asks idle owned builders to construct a solar collector, then a
Vehicle Plant, if those structures are absent. It searches nearby candidate
sites through the existing placement checks and submits begin_build; it does
not create completed structures or bypass resource payment. Unfinished owned
structures count as present to avoid duplicate orders. Destruction makes a
replacement eligible on a later decision tick.

The new base integration test starts with an Arm Construction Vehicle and the
normal 1000/1000 enemy resources, with no supplied factory. It requires two
construction starts, resource spending, enemy-owned factory products and actual
damage to a player target. All seven checks pass. This uses healthy original
builder/factory scripts and the existing provisional economy, not original AI
strategy. Site search is local; no builder relocation, resource expansion, metal
extraction or recovery of abandoned unfinished jobs is implemented yet. The
controller is still awaiting a viewer scenario.


## Viewer scenario

The Start opponent button creates one enemy Construction Vehicle at a nearby
passable, unoccupied site with room for its first build. The controller then
runs alongside normal economy and combat ticks. Repeated starts are ignored.
The opponent uses team 1's normal initial account and builds its own structures;
its units are rendered through the existing world view and accept attack clicks.

The --verify-opponent viewer check on Comet Catcher requires two construction
starts, an attack order and actual Commander damage within 6500 ticks. It passes
and is included in normal verification. This is an opt-in development scenario,
not a finished skirmish mode: no victory screen, map setup, difficulty selection,
fog, resource expansion or complete Commander weapon behavior yet.


## Interrupted construction recovery

Before starting new structures, idle owned builders now look for unassigned,
unfinished owned buildings they can build and reach. The policy resumes the
existing project through resume_build, preserving paid progress. It excludes
other teams, mobile factory products and jobs already assigned to a builder.
No relocation is attempted for out-of-range sites.

The base test interrupts construction after at least ten percent progress,
requires exactly one resume, completion of the same building and subsequent
production/attack. All ten checks pass; the Comet Catcher opponent scenario
also still passes. Builder replacement and long-distance recovery remain open.


## Scenario completion

The opt-in scenario now latches victory when no team-1 units remain, including
unfinished structures, and defeat when the player Commander is absent. Defeat
wins simultaneous elimination. Completed results stop subsequent simulation
ticks. A result dialog offers Restart, which reloads the development scene.
These are explicit rules for this asymmetric development scenario, not a claim
of complete original skirmish victory modes or mission conditions.

Six result checks cover active unfinished enemies, victory, defeat, simultaneous
elimination and result latching. The viewer test additionally removes remaining
enemies after its production/combat verification, requires victory and checks
that another step does not advance simulation. Both pass. The modal/restart
interaction itself has not yet received interactive visual verification.


## Rendered result and restart verification

The display-backed test_scenario_restart.gd fixture instantiates the real viewer,
starts the opponent, removes its forces to trigger victory, captures the embedded
result dialog and invokes its confirmation signal. Reload succeeds with a new
scene, a living Commander, no opponent and no scenario result. The captured
local/result-dialog.png was visually inspected: the centered victory message
and Restart button are legible over the battlefield. This verifies the dialog's
signal-to-reload path, not a physical mouse click. Run with Godot `--path godot
--rendering-method gl_compatibility --minimized --script res://test_scenario_restart.gd`.
It requires a rendering display and is separate from normal headless checks.
The capture stays ignored because it includes original game artwork.


## Builder replacement

If no owned Arm Construction Vehicle/Kbot exists or is queued, an idle factory
now queues its construction unit before another combat unit. In-progress builders
count as available, and a newly queued replacement suppresses duplicates from
other factories during the same decision. Construction still needs normal funds;
a stranded factory with insufficient energy and no income can stall.

The factory-only test now supplies a surviving solar collector and allows time
for builder production before combat. It requires exactly one usable construction
vehicle followed by produced combat units and target damage: nine checks pass.
The original builder-start base scenario still passes ten checks. The policy
covers absence of a builder; it does not yet replace an inaccessible, disabled
or permanently stuck surviving builder.
