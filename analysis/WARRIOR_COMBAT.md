# Warrior combat

Arm Warrior (`armwar`) now uses the shared ballistic combat path with its original
ARMWAR_LCANNON values: range 240, raw velocity 371370 per tick, reload 63 ticks
before health adjustment, area of effect 32 and default damage 60. It can be
produced by the Kbot Lab, moved, selected for practice-target controls and ordered
to attack. Its original script and model drive the firing pose and muzzle query.

The supplied-event native firing comparison passes 323 snapshots; all nine muzzle
queries return piece 1. This checks healthy script execution, not original host
cadence or damaged/death callbacks. The shared cannon test passes 14 checks for
Warrior, covering four firing directions, elevated targets and an armed duel.
The Comet Catcher --verify-warrior check builds the lab, produces and moves a
Warrior, and verifies mutual damage and one destruction against an armed Raider.
Both live checks are included in the normal verification suite.

Existing limitations include incomplete visibility rules, target leading, damage
and death callbacks, original explosion visuals/audio and full skirmish AI.

Expanded native model comparisons pass all 756 muzzle/AimFrom and 252 SweetSpot cases across seven units, including Warrior firing poses at four headings.
