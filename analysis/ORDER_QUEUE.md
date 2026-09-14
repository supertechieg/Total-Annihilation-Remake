# Unit order queue core

This checkpoint ports the per-unit order list bookkeeping that the original uses for every command. It covers:
- the order record;
- the 67-entry order table;
- how a new order is inserted and what it clears;
- the Shift-click waypoint toggle;
- the main and background dispatchers and what each handler return code does to the queue.

Handlers are not ported yet: they are injected callables. This is the base for moving the viewer's ad-hoc move, attack, build, patrol and guard orders onto one queue.

## Files

- **`godot/order_table.gd`.** The table the original builds at startup (`0x403180`, `0x406bf0`, `0x415b20` → `0x43bc90`, sorted with stricmp). Order ids are indices into the sorted table. It holds static flags (entry +0x11), runtime flag names, handler and draw addresses as ids, icons and draw masks.
- **`godot/order_queue.gd`.** The main list (unit +0x5C) and background list (unit +0x60) as Arrays with the head at index 0. Each order is a Dictionary mirroring the 0x56-byte record: type +4, state +5, mask +6, wake +0xA, target +0x16, 16.16 position +0x22..+0x2A, p36/p3a/p3e, flags +0x42, tick +0x46, pending +0x4E and goal +0x52.

## Recovered rules

- **Order constructor `0x43a0c0`.** Copies the static flags. Clears 0x200 (target) when no target is given and 0x400 (position) when no position is given. A target link is kept only for a live unit, and only while 0x200 survives.
- **Insert `0x43adc0`.**
  - A non-Shift issue of an order without 0x40 clears every main order except 0x4-protected ones. Orders that were not the head on entry get 0x10000 (skip weapon-target clear).
  - For any non-background order, even with Shift, idle (0x4000) orders at the head are removed.
  - Every issued order gets 0x1; a non-Shift issue also gets 0x2000 (acknowledge).
  - A background (0x40000) or head (0x20) order is pushed to the front of its list and inherits the old head's 0x4000.
  - Anything else goes through the marker insert `0x43ad50`: it takes the 0x1000 marker and is placed right after the order that held it, or at the tail.
- **Shift toggle `0x43afc0`.** With Shift, the first main order of the same type whose target matches (or no target passed) and whose x and z are within ±0x100000 (16 world units, inclusive, 32-bit wrap) is removed, and nothing is added. The y coordinate and p36 are ignored.
- **Patrol origin `0x43a020`.** Unless some main order already has 0x8000, a same-type order at the unit position is appended first. The calling order always gets 0x8000.
- **Factory counts `0x43b0b0`.** Positive counts are added to the p3a of a matching tail order, or a new Shift order is inserted. Negative counts are taken from matching orders, removing any that reach zero.
- **Main dispatcher `0x43b7c0`, once per unit tick, looping on the live head:**
  - A passed wake sets pending bit 1. When the mask is set and no masked event is pending, the dispatcher waits.
  - Event 0x10000 resets the aim of all three weapon slots. An empty queue creates the unit's default idle order for controller types 1 and 2.
  - Return codes:
    | Code | Effect |
    |---|---|
    | 0 | state = 0 |
    | 1 | state + 1 |
    | 2, 4 | keep |
    | 3 | wake in 30 + rand(15) ticks |
    | 5, 8 | remove |
    | 6 | rotate to tail |
    | 7 | clear both lists |
    | 9 | 0x800000; remove if the order has a successor, otherwise state 0 and wake in 30 + rand(30) |
    | > 9 | clear all |
- **Background dispatcher `0x43bad0`.** Runs every background order whose mask is clear or whose wake has passed, with event 0, and restarts from the head after each handled order. Codes 6 and 7 remove the order and stop; codes over 9 remove it.
- **Destroy `0x43a1f0`.** Sends a handler notification (event 2) when mask bit 2 is set. Stops building when 0x400000 is set, releases the goal, and clears weapon targets unless 0x10000 is set.

## Evidence

- **Oracle.** `tools/native_order_queue.py` builds the order table with the original static initialisers and checks it against a static parse. It then runs 1,500 randomized sequences, 83,350 operations in all, through the original routines:
  - issue, insert, marker insert, append, push-front-inherit, patrol append, find, count, factory count, remove, clear, rotate, main dispatch and background dispatch;
  - it dumps both full queues after every operation.
- **Stubs:**
  - allocator and delete, which record ids;
  - all order handlers, which are redirected to one scripted stub returning codes 0–9 or over 9. The stub can set mask, pending, flags and wake, and can push a new order through the original constructor;
  - the StopBuilding block, weapon-target clear `0x489800` and aim reset `0x48a0f0`, which are recorded;
  - the goal-cancel block, which is skipped because the unit movement object is null.
  - The RNG `0x4b6c30` runs natively.
- **Comparator.** `godot/compare_native_order_queue.gd` matches **511,322 / 511,322** checks: table entries, every queue field after every operation, handler calls and destroy-side events.
- **Tests.** `godot/test_order_queue.gd` passes 46 / 46 and runs in NORMAL.
- **Mutation checks.** The adversarial audit was interrupted when the session ended, so the lead ran these at integration:
  - These made the comparator fail: wake spread 16, acknowledge on Shift issues, no idle-flag inheritance, and `>` instead of `>=` for the wake test.
  - These produced mismatch output and ran past the 280 s runner limit, because the comparator prints every divergent step: toggle radius `<` instead of `<=`, marker insert before the marker holder, and ignoring 0x4 protection.
  - All were reverted, and the full match was re-confirmed.

## Limits

- **Order handlers are not ported yet.** Examples: Move `0x43c...`, Attack_Chase `0x4034a0`, Patrol, Guard, Build. They come next, with the cursor selector `0x43f0e0` (mode × unit class × hover → order type) and group issue `0x48cf30`.
- **Not wired in.** Nothing in `combat_world.gd`, `construction_world.gd` or `viewer.gd` uses the queue yet. Integration plan:
  - viewer move/attack/reclaim/build clicks become `issue()` with the cursor-selector type;
  - the existing movement, attack, ground-attack, reclaim, build and self-destruct logic becomes handler bodies returning the recovered codes;
  - each unit tick calls `dispatch()` and `dispatch_bg()` before movement.
- **Wrapped wake time.** Near tick 0xFFFFFFFF, code 3 can make the wake time wrap below the tick, and the original re-runs the head forever. The oracle bounds its handler scripts to avoid this.
