# Native wind update

`wind_state.gd` reconstructs `0x00490c40` with explicit state and random seeds. The update runs only when the unsigned deadline is strictly earlier than the current tick. It advances the previous deadline by `(floor(rand15*10/32768)+5)*30`, so a late update does not rebase the timer on the current tick.

The interval uses the CRT RNG: unsigned 32-bit seed times 214013 plus 2531011, returning bits 16..30. Strength and heading use the separate game RNG at `0x0051fc88`, equivalent to Park–Miller multiplication by 16807 modulo 2147483647 for valid positive states. Bounded requests below 2 return zero without consuming that RNG. Strength is map minimum plus a bounded draw of maximum-minus-minimum. Nonzero strength draws a new 16-bit heading; calm wind retains the old heading.

Horizontal drift is negative twice the original integer sine/cosine components of heading and strength. The routine leaves Y drift untouched. Normalized strength is strength divided by the supplied normalization field at `GAME+0x37ec8`, rounded to float32 and capped at 1. The reconstruction supports the tested nonnegative strength bounds, positive normalization and valid game RNG seed range. Initial seeding and other consumers of either RNG remain outside this component.

`native_wind_reference.py` runs the complete original wind routine, original RNG algorithms and trigonometric helpers. Only the CRT thread-storage lookup is replaced with a pointer to a synthetic record. All 600 cases match across unchanged, exact-deadline, calm, narrow-range and variable-strength updates, including final RNG states and float32 output. Eight native-derived normal checks cover the principal branches. The native comparator compares numeric fields directly, avoiding JSON reserialization's decimal precision loss.

This is not connected to world scheduling, map weather or wind-generator output yet. The initial normalization value, vertical drift initialization, map inputs and shared RNG scheduling still need integration. The shell-motion primitive already accepts a drift vector; supplying actual wind and preserving shared random ordering remains required before claiming original wind behavior in gameplay.

Run `tools/verify.ps1` for normal checks, or `-Native` for regeneration and comparison. Raw records stay in ignored `local/wind`; compact evidence is `native-wind-validation.json`.
