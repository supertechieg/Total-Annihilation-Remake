# Hammer combat investigation

## Current result

Hammer combat is now enabled. The normal suite includes an Arm Kbot Lab producing
a Hammer, selected movement, and a real Comet Catcher duel with an armed Raider.
Both units damage each other and one dies. Existing Flash and Stumpy duels pass.

The original creation path calls `0x485a40`, `0x485d40`, then weapon initialization
`0x49e070`. The prototype incorrectly deferred launch-offset capture until first
attack, after factory exit and movement had changed heading and pose. It now
captures primary muzzle/AimFrom separation immediately after Create, using the
host's default creation heading 32768, and preserves it for subsequent attacks.
The complete native creation path (including original heading randomization) is
not yet reproduced; this fixes the demonstrated lifecycle ordering error.

Before the fix, Hammer impacts in the duel overshot the Raider by roughly 84–91
world units. With creation-time capture, one alternating barrel hits the Raider.
The other still overshoots in this setup; both barrels hit in a flat test arena.
Further accuracy work must investigate that remaining geometry/trajectory case.

## Earlier failed experiment

The Hammer firing script matches 323 original-interpreter snapshots at supplied
callback times. QueryPrimary alternates piece indices 1 and 2, exercising both
barrels. The shared real-model native comparisons now include Hammer firing
poses: 432 total muzzle/AimFrom cases and 144 total SweetSpot target cases across
Flash, Raider, Stumpy and Hammer all match.

Hammer combat is not enabled. An experimental factory-produced Hammer duel on
Comet Catcher failed: the Raider took no damage before destroying the Hammer.
Both units together produced 27 shots and 16 damage events; the Raider's health
remained at its initial 1058. The initial Hammer launch offset was positive
558860, so the previously encountered negative unsigned offset does not explain
this failure. The experimental combat/viewer changes were removed.

Next investigate Hammer projectile trajectories and impact positions, including
the two barrel origins, AimFrom height, angle use and initial launch adjustment.
Passing isolated script/geometry checks does not establish a correct shot host.
The native fixture uses supplied firing times, not original shot scheduling,
and does not exercise walking-to-firing transitions.

Run `python tools/native_firing_reference.py --unit armham`, then Godot headless
with `--path godot --script res://compare_native_firing.gd -- --armham`.
The optional native suite generates this trace before the shared geometry tests.
