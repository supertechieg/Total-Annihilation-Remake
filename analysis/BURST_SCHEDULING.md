# Original projectile-owned bursts

## Live Flash integration

WeaponCycle now dispatches one burst source with one QueryPrimary/FirePrimary
pair per reload. Combat advances that source independently of subsequent orders,
uses its cached piece name for position refresh, and applies verified source
spread after copying. Flash rounds appear at dispatch +3/+6/+9 ticks. Copies are
appended after current projectile movement, matching the pool snapshot boundary.
Stop prevents new dispatches while already-created bursts finish.

`test_burst_combat.gd` checks the exact emission ticks, deferred movement and
post-Stop completion using a live Flash script. The normal suite and Flash,
Stumpy and Hammer factory duels pass. The existing weapon-cycle tests now assert
dispatch counts instead of the obsolete per-round script callback policy.

Remaining host limitations: the initial EMG direction still uses the existing
normalized-vector approximation; emitted rounds retain the previous range-based
expiration instead of consuming the verified copied deadline. RNG starts at a
fixed seed independent of other world random consumers. Source death currently
cancels outstanding bursts as a provisional teardown rule. Original pool capacity,
sounds, duration randomness and health/experience reload settlement remain pending.
The currently supported cannons have no burst field; their single-shot path is
unchanged. Arbitrary ballistic bursts are not yet connected.

## Recovered native behavior

Tracing `0x49b720` changes the implementation plan for weapon cadence. Burst
scheduling belongs to projectile records, rather than repeated script firing
callbacks in the unit weapon controller. This is static executable/decompiler
evidence, now supported by the controlled native transition test below.

The loader stores `burst` at weapon `+0xea`, `burstrate` at `+0xec` and
`sprayangle` at `+0xee`. Launchers including `0x49c9c0` and `0x49cde0` copy burst
count into projectile `+0x60`. Projectile updater `0x49b720` branches on this
field: zero advances a normal projectile; nonzero follows the burst scheduler.
Consequently the initial record is a burst source, not an ordinary moving shot.

When unsigned `source_timestamp + interval <= game_tick`:

- If interval exceeds four ticks or the remaining count is odd, refresh source
  position with `0x43e240`, using the cached piece index at projectile `+0x62`.
- Decrement the burst count and advance the source timestamp by the interval.
- Allocate and copy a 0x6b-byte projectile record, subject to the original temporary
  capacity of 300. The original decrements count even when allocation fails.
- Set the copy's timestamp to current tick, recompute its expiration, apply
  optional duration randomness, and clear the copy's burst count.
- Optional spray changes the source record's X/Z velocity after the copy; this
  ordering must be tested rather than applying spread directly to each copy.
- Once the source count reaches zero, mark it for removal.

The updater snapshots the projectile count before its loop. Newly appended copies
are not processed by that loop during the same invocation. No FirePrimary callback
appears in the burst-copy branch; that callback occurs in the original launcher.

The current WeaponCycle calls QueryPrimary/FirePrimary for every burst round and
emits its first round immediately. Its existing tests establish that provisional
policy, not native burst timing. They must change with the host reconstruction.
The new reload arithmetic should be settled on successful initial dispatch,
independently of the projectile-owned remaining burst. Stop/cancel, source death,
cached piece validity and allocation timing require oracle coverage before use.

Next build a native `0x49b720` fixture containing a burst source with movement,
collision, sounds and random-spread paths controlled explicitly. Compare successive
ticks, copy contents, callback counts and source removal, including odd/even rounds,
interval boundaries, capacity exhaustion and timestamp wraparound.

## Controlled native transition validation

`native_burst_update.py` executes complete `0x49b720` on one burst source, with
the muzzle-position callback supplied and final pool consolidation disabled.
`burst_schedule.gd` matches 240 cases for source/copy positions, timestamps,
remaining counts, expiration, removal flags and refresh invocation. Cases cover
counts one through five, intervals 0/1/3/4/5/30, explicit and calculated lifetime,
and unsigned due boundaries. The source and copy are inspected separately.

The fixture now retains each native source across subsequent increasing tick
values (with unsigned wrap), while advancing the supplied muzzle position. All
1,200 transitions across 240 sequences match. Copies are removed from the fixture
pool between updates so their independent movement/collision is excluded. The
query hook checks that refresh retains unit, slot zero and cached piece index two.
The Godot comparison carries its own previous state forward rather than replacing
it with native state, exposing cumulative count/timestamp errors.

Sounds, duration randomness, full pool capacity, source death and actual cached piece transforms still
need coverage. It does not verify all copied bytes or replace the live burst host.
Run `python tools/native_burst_update.py` followed by Godot headless with
`--path godot --script res://compare_native_burst.gd`. The optional native suite
includes both; raw traces remain under ignored `local/burst`.

## Spread and random-state validation

The same 1,200 transitions now include spray angles 0, 1024 (Flash EMG) and 5000,
random headings/pitches, arbitrary starting velocities and seeded original game
randomness. The native fixture executes `0x4b6c30`; it does not replace the random
function. Comparison checks source and copy velocity plus final RNG state after
each transition, using the already reconstructed game RNG.

`Burst.apply_spread` modifies source X/Z velocity after copying, using the source
heading minus half the spray angle plus the bounded random draw. It preserves
source Y velocity and stored heading/pitch. The emitted copy retains the prior
velocity. All transitions match, including sequential RNG advancement. This
helper remains separate from the live host pending burst integration.
