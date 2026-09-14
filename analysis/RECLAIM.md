# Reclaim

Units with `canreclamate=1` can now reclaim wrecks and other reclaimable features. The feature's metal and energy are credited to the reclaimer, and the feature is replaced by its `featurereclamate` (a smudge for unit wrecks).

## Recovered original behavior

- **Order handler `0x4147b0`.** A state machine on the order byte `+5`, with its jump table at `0x414a6c`.
  - **Entry gate.** Any state first requires feature flag `0x80` (reclaimable); otherwise the handler returns 8.
  - **State 0 (`0x4147f4`).** Requires the unit's reclaim capability bits (`def+0x241 & 0x800`, `def+0x245 & 0x400`) and sets the "Reclaiming" status. Mobile units (`type & 3 == 1`) create a move child order.
    - The value passed to `0x44e6c0` is `cruisealt/2` (`def+0x21c`; builddistance is `+0x212`). `0x44e6c0` turns it into an altitude above `max(terrain height, sea level)`, so it matters only for aircraft.
    - The range rule the ground child order uses has not been traced.
  - **State 1 (`0x4148cc`).** Creates a second child order (flags `0xe0`).
  - **State 2 (`0x414904`).**
    - Sets the countdown `order+0x36 = ftol(30.0 - (metal + energy) * -0.5)`, using definition metal `+0xf0` and energy `+0xec` (constants at `0x4fcc50`/`0x4fcc54`).
    - Plays sound 11 through `0x47f780` for the local player.
  - **State 3 (`0x414955`).**
    - `0x439e80(order, 2)` sleeps the order for two ticks, then the countdown is reduced by 2. While it stays positive, `unit+0xb0 = tick + 300`, and nano particles (`0x472200`) are emitted while the countdown is above 30.
    - Returns 2 while running and 1 once the countdown reaches zero.
  - **State 4 (`0x414a44`).** Calls `0x4237d0(unit, position)` and returns 5.
- **Completion `0x4237d0`.**
  1. Resolves the feature at `position >> 20`, following continuations to the anchor.
  2. Adds the definition energy to the unit income accumulator `+0xbc` and metal to `+0xd4`. An AI multiplier applies only for controller type 2.
  3. Calls `0x423550(x, z, 1)`. Through `0x423710` this removes the feature with `0x4246b0` and places the definition's `featurereclamate` (`+0xf8`) at the same anchor and instance position with owner 10. Parameter 0, used for destruction, places `featuredead` instead.
- **Timing.** The countdown depends only on the feature's value, not on the builder's `workertime`. Because each run sleeps two ticks and subtracts two, the reclaim takes about `countdown` ticks.

## Implementation

- **Bundle.** `prepare_units.py` adds `featurereclamate` to the feature runtime (`feature_runtime_version=2`; the launcher regenerates older bundles).
- **Feature replacement.** `FeatureWorld.replace(cell, reclaimed)` implements `0x423550`/`0x423710`.
- **`ConstructionWorld` reclaim jobs.**
  - `can_reclaim` checks completion, `canreclamate`, and whether the unit is a scripted mobile unit or the Commander.
  - `reclaim(source, cell)` resolves the feature anchor from any covered cell and rejects features that are not reclaimable. It stops the unit's current build or reclaim and routes out-of-range builders to an approach point.
  - `step_reclaimers` runs the states:
    1. Wait until within build distance and stopped.
    2. Call `StartBuilding` with the heading to the feature and wait for the construction arm (script value 5).
    3. Set the countdown, then sleep two ticks per run while subtracting two.
    4. Complete.
  - `complete_reclaim` adds energy and metal to the reclaimer's `energy_ledger`/`metal_ledger` income, so the next settlement adds them to stock. It replaces the feature, calls `StopBuilding`, refreshes feature blocking and records the result in `reclaimed`.
  - **Cancellation.** Move orders, new builds, `stop_build`, removing the unit or losing the feature all end the job.
- **Viewer.** Clicking a reclaimable feature orders the selected builder, or the Commander, to reclaim it. The status line shows the job state.

## Evidence

- `test_reclaim.gd` passes 50 checks:
  - **Rules.** The countdown formula, and replacement by `featurereclamate` and `featuredead`, including position, owner and footprint.
  - **Construction units.** For `armcv` and `corck`:
    - approach from out of range, with the construction arm ready inside build distance;
    - the countdown taken from the definition, and the finish timing;
    - the wreck becoming `smudge01` and no longer blocking navigation;
    - metal credited to income and then stock;
    - rejection of the smudge;
    - cancellation by a move order (with `StopBuilding`) and by feature removal.
  - **Other units.** The minelayer is rejected, and the scriptless Commander can reclaim.
- `--verify-reclaim` on Comet Catcher runs for both factions in NORMAL verification. The Commander destroys an adjacent enemy, then reclaims the wreck through the viewer click handler:
  - Arm: `corraid_dead`, 135 metal, countdown 97, finished 180 ticks after the order, metal 6 → 142.
  - Core: `armflash_dead`, 85 metal, countdown 72, finished 159 ticks after the order, metal 6 → 92.
- The handler, countdown and completion come from disassembly. They have not yet been executed natively.

## Limits

- **Approach range and aiming.** Both are provisional: the host uses build distance to the feature footprint and turns only through `StartBuilding`. The move and aim child orders are not traced.
- **Scheduling.** The host advances to the next state on the tick after a state returns 1, which could be a tick off from the original scheduler.
- **Not implemented.**
  - The AI multiplier, reclaim sound, nano particles and the `unit+0xb0` timer.
  - Reclaiming living units, and area or patrol reclaim.
  - The `order+0x40` flag gate in state 2.
- **Storage cap.** Reclaimed resources above storage are lost at settlement, as the stock is capped.
