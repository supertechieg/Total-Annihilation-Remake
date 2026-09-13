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


## Rendered overlay inspection

render_weapon_effects.gd renders the actual combat_overlay.gd with first, middle
and last frames of fx/explode2 through fx/explode5, using preserved offsets.
A compatibility-renderer capture was produced and visually inspected at
local/weapon-effects/overlay-preview.png. The fixture explicitly sets content
scale to its 720x480 capture size. Explosions show transparent backgrounds and
distinct native frame sizes. Late frames contain small colored specks; native
palette special-color/blending treatment is not established, so these are left
unchanged pending comparison. This fixture is not a full battlefield or original
renderer comparison and does not establish animation timing.

Run Godot with `--path godot --rendering-method gl_compatibility --minimized
--script res://render_weapon_effects.gd`. This requires a rendering display;
ordinary headless dummy rendering cannot provide the captured image. Captures
contain game artwork and remain under ignored local content.
