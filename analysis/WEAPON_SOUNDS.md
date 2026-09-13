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
scheduler. EMG terrain-only impacts now request the stored impact sound. These are outstanding
fidelity tasks, not claims of original audio behavior.


## Mixer capture verification

The normal verification suite now runs test_weapon_audio.gd. It explicitly
enables playback under the headless driver, captures the mixed original
canlite3 WAV through AudioEffectCapture and requires nonzero samples. It also
checks idle-player reuse, the 32-voice limit under overlapping requests and
that disabling playback prevents new requests. All five checks pass. Normal
headless viewer runs remain silent by default. The captured-buffer check
verifies software mixer output, not physical speakers, subjective balance or
native audio timing. Preparation of local weapon sounds is now required for
this verification suite.


Ground-impact regression checks verify exactly one sound/explosion event when a
direct round crosses below terrain, no unit-hit count increment, and silent
removal when its deadline is reached before that movement. The full combat test
passes 27 checks and burst scheduling still passes 12. This fills the feedback
hole in the existing endpoint terrain test; native sound timing and terrain
collision interpolation remain outside the check.
