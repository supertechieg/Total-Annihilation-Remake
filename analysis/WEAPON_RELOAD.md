# Normal weapon reload settlement

## Live integration

Combat now supplies current health, maximum health and the unit's experience
field to the verified arithmetic at dispatch. WeaponCycle settles its next reload
after a successful firing callback; projectile-owned burst copies do not settle
it again. Later health changes affect the next dispatch, not the current timer.
Experience defaults to zero; automatic experience accrual is not yet implemented.

The live regression starts a half-health Raider (529/1058) and confirms a 49-tick
reload. Restoring health and supplying experience 25 during that reload leaves
the timer unchanged; the next dispatch settles 31 ticks. All five regression
checks, the normal suite and three factory duels pass. Original global countdown
scheduling and stopped-unit timer advancement still need broader host comparison.

## Native arithmetic evidence

Original host `0x49e1a0` settles reload after a successful weapon dispatch.
The arithmetic at `0x49e468..0x49e4f2` reads unit experience at `+0xb8`, signed
health at `+0x108`, definition maximum health at `+0x1fa` and weapon reload ticks
at `+0xe4`. Experience divided by five is capped at five; each rank subtracts
six from the reload percentage. The health multiplier is 120 minus twenty times
current health divided by maximum health. Both percentage stages truncate
separately, and the final timer is stored as a 16-bit value.

For base reload 58, full health and zero experience yield 58 ticks; half health
yields 63. At rank five, full health yields 40 and half health yields 44.

`weapon_reload.gd` matches 600 original executable cases across valid nonnegative
signed-short health values, reload values and rank boundaries. The oracle enters
the original arithmetic block and returns immediately after timer assignment.
This is not a comparison of the complete weapon scheduler.

Stockpiled weapons use a different branch and are excluded. Experience accrual
and exact unit health storage are separate unfinished host work.

Further tracing found that original bursts are scheduled by projectile records,
not repeated unit firing callbacks. See [BURST_SCHEDULING.md](BURST_SCHEDULING.md)
for the recovered branch and the native fixture needed before integration.

Reproduce using `python tools/native_weapon_reload.py` and Godot headless with
`--path godot --script res://compare_native_weapon_reload.gd`. Both steps are in
the optional native suite; raw test inputs remain ignored under `local/`.
