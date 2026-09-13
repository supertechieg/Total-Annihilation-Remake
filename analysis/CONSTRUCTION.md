# First construction loop

The Commander can now place nearby structures, spend metal and energy over time, finish construction, stop and resume unfinished work, and gain production/storage from completed structures. Select a unit from the build dropdown, choose **Place selected structure**, then click nearby terrain. Right-click/S pauses work; click an unfinished structure to resume. Move the Commander closer if placement or resumption is out of range.

The first verified playable example is the Arm Solar Collector on Comet Catcher. The Commander uses its original StartBuilding/StopBuilding pose callbacks. The new structure uses its original model and textures, with transparency showing progress. Arm solar collectors now run Create during construction and Activate on completion. Clicking a completed collector toggles its energy production and original opening/closing script. Each collector has an independent VM and animated model instance.

## Native comparison

`tools/native_construction_reference.py` executes original x86 routine `0x0041ba60` with synthetic builder, target and definition records. Its positive-work path calls the original request routine `0x004011c0`. The builder/target omit live-unit flags, deliberately preventing completed-unit activation/UI side effects. Negative work/reclaim is not tested.

`construction_math.gd` reproduces positive construction work: remaining fraction decreases by work divided by BuildTime, clamps to 0–1, and is stored as float32. Resource requests are based on the actual rounded progress delta. Health increases by the difference between truncated remaining-health quantities, capped at maximum health. Requests are recorded even when rejected; acceptance requires both existing resource debt fields to be nonpositive. This request routine does not immediately deduct from player balances.

All 1,000 seeded cases match, including zero work, already-complete targets, partial work, completion overshoot, and resource-debt rejection. Floating outputs are compared by their **float32 bits**. An initial decimal JSON roundtrip produced false differences; the verifier now compares the representation actually stored by the original engine. Five input/output fields are not enough to prove full construction lifecycle fidelity; the comparison's exact scope is recorded in `analysis/native-construction-validation.json`.

## Provisional host systems

`construction_world.gd` provides the current runnable host around the verified primitive. These parts remain provisional:

- Work rate is WorkerTime / 30 per simulation tick. The original caller's timing is not yet verified.
- Resources settle immediately per tick. Insufficient funds stall the full work increment. Original deferred debt settlement (identified at `0x00401360`) is not yet reconstructed.
- Production/storage use the selected definitions. Negative EnergyUse produces energy while active; e.g. the Commander plus completed solar produce 45 energy/second, or 25 with solar disabled. Extractor terrain-metal sampling, wind, tide, metal conversion, other activation scripts and special-unit production remain unfinished.
- Starting resources/storage are 1,000 each. They are prototype host defaults, not recovered game setup rules.
- Build range measures to a footprint edge. Footprints, height-range slope checks, water checks, collision-grid reservations and arrival/placement semantics need original-engine comparison.
- One Commander task runs at a time. New build orders leave prior unfinished structures paused. Arm Vehicle Plants and Kbot Labs produce queued menu entries; see FACTORIES.md. Arm Construction Vehicles, Construction Kbots and Minelayers now have independent build jobs and menus; see MOBILE_BUILDERS.md.
- The host has a configurable `unit_limit` field, default 1,000 including the Commander. This is a capacity setting, not a demonstrated battle-performance limit.
- Arm solar and enabled factories use animated viewports per instance. Produced mobile units also have separate views for heading changes; other building types retain static views cached per type. This has not been benchmarked for large armies. Depth sorting, original construction effects and exact scale/projection remain unfinished.

## Verification

`tools/verify.ps1 -Native` passes the existing parser/catalog/model/COB/navigation checks, 22 construction host checks, 1,000 native construction cases, 606 solar interpreter snapshots, and a real-map integration test. Host checks include production while enabled/disabled, closed panel rotations, independent collector states and reactivation. The integration test completes a nearby solar collector, verifies zero remaining work, nonnegative balances, a fully visible structure and fault-free scripts, then disables and re-enables it. A rendered completed-structure capture was inspected.

`native_solar_reference.py` executes the original interpreter with healthy (property 4 = 100) and build-percent (17) host inputs. The trace covers Create, construction completion input, Activate, Deactivate, and reactivation while closing. Every piece position, rotation, speed, target, visibility, static, thread PC/state and written value matches in 606 snapshots. This proves script execution with those supplied inputs, not original world callback timing or damage behavior. The host currently supplies healthy status throughout construction; damaged smoke (RAND/EMIT_SFX), destruction, HitByWeapon activation coupling and property 20's damage effects remain unimplemented. Native world rounding of property 17 is also unverified.

Capture a completed example with Godot `--path godot -- --construction-demo --capture ABSOLUTE_PNG_PATH`. This demo fast-forwards 600 ticks before capture; ordinary play advances at 30 ticks per second.

Next: remaining building/unit COB callbacks, more faithful resource settlement/production, mobile builders, weapons and actual combat. Initial factory queues and product selection now work; see FACTORIES.md. The full-game goal remains active.
