# Beam laser weapons

Arm Jeffy (`armfav`), Core Weasel (`corfav`), Core Instigator (`corgator`) and Core A.K. (`corak`) now fight with their original beam lasers. These are the only level-one ground units whose weapons set `beamweapon=1`.

## Recovered original behavior

- **Loader.** `beamweapon` sets bit 3 (`0x8`) of the weapon flag word at weapon record offset `0x111`. `duration` is converted at `0x42e67c..0x42e687` with the same binary64 ×30 constant as `burstrate` and stored as a 16-bit word at `+0xf0`. Shipped lasers use `.02`, which truncates to 0 ticks.
- **Launch.** The launch dispatcher `0x49d270` sends line-of-sight weapons that are not ballistic or vertical-launch to the direct launcher `0x49c9c0`, the same path as E.M.G. rounds. Shared initialization `0x49c740` copies the muzzle position into both the head (`+0x04`) and the tail (`+0x10`), clears tail-release bit 0 of `+0x69`, and stores the launch tick at `+0x42`. The deadline is `(range << 16) / speed` ticks unless speed is zero or `noautorange` is set.
- **Update.** In `0x49b720`, a live line-of-sight round moves its head by velocity. Only when flag `0x8` is set: an unreleased tail becomes released once `launch + duration` is strictly earlier than the current tick, and a released tail moves by the same velocity. The release tick does not move the tail, so a 0-tick duration beam is about two ticks of travel long. Expiration (tick at or past deadline) marks the round removed before any movement. No other code in the executable reads the beam bit.
- **Collision and damage.** Beams go through the same endpoint collision `0x49b090` and impact dispatch as other direct rounds. No beam-specific hit, sweep or damage logic was found.

## Evidence

- `native_weapon_reference.py` / `compare_native_weapons.py`: 1,645 of 1,645 loader conversions match, including 206 `duration` cases (all 193 shipped weapons plus boundaries such as `.03333…` → 0, `.04` → 1, negative → wrapped word). Weapon runtime schema is now 5 with `duration_ticks`; the launcher regenerates older bundles and the catalog rejects entries without it.
- `native_beam_motion.py` / `compare_native_beam_motion.gd`: 600 of 600 executions of the complete `0x49b720` match `beam_motion.gd`. Cases cover beam and non-beam rounds, released and unreleased tails, the strict release boundary, durations 0, 1, 2, 6, 30 and 65535, 32-bit wrap, and expiration. Collision and pool consolidation are stubbed. Summary: native-beam-motion-validation.json.
- Firing scripts match the original interpreter: Jeffy 325, Weasel 325, Instigator 325, A.K. 322 (1,297 total), with HitByWeapon exercised for the three scripts that define it. Real-model muzzle/AimFrom origins now total 1,944 cases and SweetSpot target points 648, all matching.
- `test_beam_combat.gd` (18 checks per unit, all four pass) verifies: native deadline at launch, tail at the muzzle while the head has moved on the launch tick, tail release exactly one tick after launch, damage, firing sound, a two-way duel, four firing directions and an 8-unit raised target.
- Real Comet Catcher factory duels pass for all four units (`--verify-armfav`, `--verify-corfav`, `--verify-corgator`, `--verify-corak`; Core flags boot the Core faction). All run in normal verification.

## Limits

- **Terrain contact now uses the native rule** (see PROJECTILE_COLLISION.md). At the 24-unit plateau test, A.K. and Jeffy beams now reach the target. Weasel and Instigator beams end in the plateau's first cell (integer height 23 against a lowest corner of 24), which the original test also ends given the same aim. The earlier cut-off at x≈605 was the host's nearest-sample rounding, now removed. The test records the 24-unit case rather than asserting a hit for every unit.
- Rendering is a development red line from tail to head. Original laser palette colors (`color`/`color2`), glow and lighting are not reproduced. A rendered duel capture was inspected, but no beam was in flight on the captured frames because beams are short-lived; beam state is asserted by the host test instead.
- Newly launched beams move on their launch tick, matching the existing direct-round host order. Native order between weapon firing and projectile update within a frame is not yet compared.
- No energy-per-shot cost (these lasers have none), damage-state script callbacks, or AI changes.
