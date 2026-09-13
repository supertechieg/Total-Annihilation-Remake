# Original blast falloff

The area damage path at `0x0049a120` uses half the weapon's area-of-effect value as radius. For unit targets it measures blast distance to an axis-aligned box translated by the unit position, using unit-definition minimum XYZ at +0x15e and maximum XYZ at +0x16a. Each axis contributes zero when the blast lies within that interval; otherwise it contributes the distance to the nearest face. The routine takes the Euclidean length of those gaps, truncates the fixed-point length and extracts its integer part before comparing with the radius.

Targets at or beyond the radius are excluded. Distance zero receives multiplier1. Otherwise the multiplier is `(1-edge)*(distance/radius-1)^2+edge`, stored as float32. It is quadratic, not linear. Even sub-unit separation truncates to distance zero. The edge value comes from weapon+0xd8. The impact dispatcher at `0x00499eb0` uses direct target damage for area-of-effect values below17 when a unit was hit; other impacts go through area enumeration. The radius for the Raider's area32 is therefore16.

`splash_damage.gd` reconstructs the isolated box-distance and falloff calculation. `native_splash_reference.py` runs original instructions at `0x49a2aa` through the pre-damage boundary at `0x49a3ee`, with the outside-radius exit at `0x49a411`. Only those boundaries are replaced by returns. All600 cases match, including600 supplied box/position/radius/edge configurations with six explicit distance boundaries. Six native-derived fixtures run in normal verification. See `native-splash-validation.json`; raw cases stay local/splash.

This does not yet connect splash to world combat. Native box generation, spatial enumeration/deduplication, feature damage, source exclusion and the damage dispatcher need integration. The dispatcher also applies unit-specific damage, float multiplier truncation, attacker experience and global damage flags before health handling; those are not implemented by this falloff primitive. Coordinate overflow and signed16 extracted distances beyond normal weapon ranges are outside the tested domain. Binary64 geometry is compared to the original x87 calculation for these cases, not proven for every precision boundary.

## Unit box reconstruction

The definition loader's block `0x42d080` through `0x42d125` computes X/Z bounds as plus/minus footprint times eight world units. Y minimum is zero; the later model load calls `0x4cb5f0` to obtain Y maximum. That recursive routine starts each sibling group at zero, takes the maximum of each vertex Y plus its piece offset, and compares child-group height plus the parent's offset. It uses unanimated model geometry, not current COB pose or heading.

`unit_bounds.gd` reproduces this height traversal and ordinary positive footprint bounds. `native_unit_bounds.py` relocates original 3DO vertex/child/sibling pointers, runs the original axis conversion and full recursive height routine, then executes the footprint arithmetic block. All 272 prepared units match on all six bounds. Seven native-derived checks cover the currently playable unit types. See `native-unit-bounds-validation.json`. Extreme signed16 footprint overflow is outside this reconstruction's supported domain.

These are the boxes consumed by area damage. They are not yet connected to combat, and this comparison does not prove direct projectile intersection, spatial enumeration, or world placement. Existing footprint-based spheres remain provisional until the intersection path is recovered.

## Damage selection and scaling details

`weapon_damage.gd` reconstructs `0x499cd0` up to health dispatch. A matching unit-name override replaces the unsigned16 default damage. Prepared definition keys are lowercase; native lookup is case-insensitive. The integer base is multiplied by a float32 multiplier and truncated. With an attacker, the result receives a bonus of six percent for each five experience points, capped at thirty percent, with integer truncation after multiplication. Global flags 0x80 and 0x100 then double and halve damage, respectively, in that order.

`native_damage_reference.py` executes the whole original routine with only health dispatch `0x489bb0` stubbed. All 600 cases match, covering absent/matching/nonmatching overrides, five multipliers, experience values, both global flags and absent attackers. Nine native-derived regression checks run without the executable. See `native-damage-validation.json`. This covers the sampled positive damage domain, not every overflow or x87 precision boundary.

Flash direct hits now use this helper with multiplier1 and zero experience/flags. Experience accrual and game-mode flags are not yet world systems; armor, health handling, kills and damage callbacks remain unverified. Splash itself remains unconnected. Next recover unit bounds and remaining health dispatch, then connect Raider shell collisions and area damage with the ballistic and environment primitives.
