# Original weapon explosion artwork

Run `python tools/prepare_weapon_effects.py` after unit preparation. It extracts
all referenced land/water/lava explosion animations through the existing GAF
parser and provisional archive precedence: 15 animations, 208 RGBA frames,
no missing references. Frame offsets and source hashes are stored in the ignored
local/weapon-effects index. Original assets are not distributed in Git.

weapon_effects.gd caches loaded textures. All 208 frames pass Godot loading,
dimension and cache checks. Combat projectiles retain their land explosion key;
unit impacts and shell/rocket blasts create an effect of the matching frame count.
The overlay draws those frames with their GAF offsets. Missing artwork uses the
previous circle fallback. Animation duration is provisionally one frame per
30 Hz simulation tick. Water/lava assets are prepared but environmental selection
is not wired. Native timing, blending, elevation projection and rendered visual
appearance have not yet been verified. Original explosion damage is unaffected.

The Samson factory duel and 16 cannon combat checks pass after integration.
