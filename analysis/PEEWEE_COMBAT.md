# Peewee combat

Arm Peewee (`armpw`) now uses the shared EMG combat path: original weapon values,
native-compared launch math, projectile-owned bursts and spray, endpoint collision,
deadline expiration and health-based reload. It can be produced by the Arm Kbot
Lab, selected, moved and ordered to attack. Practice and armed-Raider controls
accept a selected Peewee.

Verification includes 323 original-interpreter snapshots at supplied firing
callback times. QueryPrimary alternates between piece indices 3 and 4. Shared
real-model checks now cover five combat units: all 540 muzzle/AimFrom cases and
180 SweetSpot cases match, including Peewee firing poses at four headings.
These fixtures do not prove the original scheduling of the supplied callbacks.

`--verify-peewee` builds the lab, produces and moves a Peewee, then runs its duel
against an armed Raider on Comet Catcher. Both take damage and one is destroyed.
This check is included in the normal suite. Existing combat limitations still
apply, including absent experience accrual, full visibility rules, sound/effects
and damage/death script callbacks. Healthy script tests do not cover smoke or
every walking-to-firing transition.
