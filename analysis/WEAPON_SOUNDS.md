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
an audible listening test. Combat event playback and mixing remain to be wired.
