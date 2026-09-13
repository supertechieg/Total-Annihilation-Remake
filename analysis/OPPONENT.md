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
