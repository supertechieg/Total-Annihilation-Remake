# Original weapon sounds

Run `python tools/prepare_weapon_sounds.py` after preparing unit data. It resolves
soundstart, soundhit and soundwater names through the existing provisional archive
profile and writes WAVs plus source hashes/metadata under ignored local/weapon-sounds.
All 60 referenced sounds are present. The original installation is read only.

weapon_sounds.gd decodes streams on demand and caches repeated names. The headless
test_weapon_sounds.gd check passes all 60 sounds, verifies durations against WAV
frame counts/sample rates and verifies stream reuse. Godot warns about one-byte
size discrepancies in several original WAVs, but decodes them with the expected
duration. Source bytes are retained unchanged. This is decode verification, not
an audible listening test. Combat event playback is connected as described below.


## Live playback

The viewer connects combat sound_requested events to weapon_audio.gd. Firing
cycles request soundstart at the muzzle, direct unit impacts request soundhit,
and shell/rocket blasts request soundhit once per explosion. Projectile records
retain their impact sound so it remains available after the shooter disappears.
Missing/empty sounds do not stop simulation. The audio node caches decoded WAVs,
reuses idle players and caps playback at 32 voices with replacement when full.
Headless verification skips playback so accelerated simulation does not emit
compressed audio bursts.

The cannon test now verifies named firing and impact events (16 checks total).
Burst and rocket regression tests pass, as does the headless Samson factory duel.
The WAV decode test previously verified all 60 streams. Audible device output
has not been listened to or captured. Mixing is provisional: nonspatial playback
at -12 dB, no original distance attenuation/priority, no water-sound selection,
and firing events follow script cycles rather than a native-verified audio
scheduler. EMG terrain-only impacts still lack an event. These are outstanding
fidelity tasks, not claims of original audio behavior.
