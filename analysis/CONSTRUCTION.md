# First construction loop

The Commander can now place nearby structures, spend metal and energy over time, finish construction, stop and resume unfinished work, and gain production/storage from completed structures. Select a unit from the build dropdown, choose **Place selected structure**, then click nearby terrain. Right-click/S pauses work; click an unfinished structure to resume. Move the Commander closer if placement or resumption is out of range.

The first verified playable example is the Arm Solar Collector on Comet Catcher. The Commander uses its original StartBuilding/StopBuilding pose callbacks. The new structure uses its original model and textures, with transparency showing progress. It does not yet execute its own building script, so the solar panels currently remain in the unanimated model pose.

## Native comparison

`tools/native_construction_reference.py` executes original x86 routine `0x0041ba60` with synthetic builder, target and definition records. Its positive-work path calls the original request routine `0x004011c0`. The builder/target omit live-unit flags, deliberately preventing completed-unit activation/UI side effects. Negative work/reclaim is not tested.

`construction_math.gd` reproduces positive construction work: remaining fraction decreases by work divided by BuildTime, clamps to 0–1, and is stored as float32. Resource requests are based on the actual rounded progress delta. Health increases by the difference between truncated remaining-health quantities, capped at maximum health. Requests are recorded even when rejected; acceptance requires both existing resource debt fields to be nonpositive. This request routine does not immediately deduct from player balances.

All 1,000 seeded cases match, including zero work, already-complete targets, partial work, completion overshoot, and resource-debt rejection. Floating outputs are compared by their **float32 bits**. An initial decimal JSON roundtrip produced false differences; the verifier now compares the representation actually stored by the original engine. Five input/output fields are not enough to prove full construction lifecycle fidelity; the comparison's exact scope is recorded in `analysis/native-construction-validation.json`.

## Provisional host systems

`construction_world.gd` provides the current runnable host around the verified primitive. These parts remain provisional:

- Work rate is WorkerTime / 30 per simulation tick. The original caller's timing is not yet verified.
- Resources settle immediately per tick. Insufficient funds stall the full work increment. Original deferred debt settlement (identified at `0x00401360`) is not yet reconstructed.
- Production/storage use the selected definitions. Negative EnergyUse produces energy while active; e.g. the Commander plus completed solar produce 45 energy/second. Extractor terrain-metal sampling, wind, tide, metal conversion, activation scripts and special-unit production remain unfinished.
- Starting resources/storage are 1,000 each. They are prototype host defaults, not recovered game setup rules.
- Build range measures to a footprint edge. Footprints, height-range slope checks, water checks, collision-grid reservations and arrival/placement semantics need original-engine comparison.
- One Commander task runs at a time. New build orders leave prior unfinished structures paused. Factories and construction units do not yet build their own menu entries.
- The host has a configurable `unit_limit` field, default 1,000 including the Commander. This is a capacity setting, not a demonstrated battle-performance limit.
- Building presentation uses a static viewport cached per unit type. Per-building animated poses, depth sorting, original construction effects and exact scale/projection are unfinished.

## Verification

`tools/verify.ps1 -Native` passes the existing parser/catalog/model/COB/navigation checks, 15 construction host checks, 1,000 native construction cases, and a real-map integration test. The integration test completes a nearby solar collector, verifies zero remaining work, nonnegative balances, a fully visible structure and a fault-free Commander script returning from construction. A rendered completed-structure capture was inspected.

Capture a completed example with Godot `--path godot -- --construction-demo --capture ABSOLUTE_PNG_PATH`. This demo fast-forwards 450 ticks before capture; ordinary play advances at 30 ticks per second.

Next: building COB engine callbacks and activation, more faithful resource settlement/production, factory build orders, unit selection, weapons and actual combat. The full-game goal remains active; this is a playable construction checkpoint, not completion of Total Annihilation.
