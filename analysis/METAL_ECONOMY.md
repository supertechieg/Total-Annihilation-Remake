# Renewable metal reconstruction

Prepared armmakr has makesmetal=1 and energyuse=60; armmex has extractsmetal=.001
and energyuse=3. These differ from unconditional metalmake. The original loader
stores makesmetal as a byte at definition +0x22d and extractsmetal as float at
+0x1ce. The resource update gates maker/extractor output on its energy-payment
branch. Extractor setup at 0x437840 sums map-cell metal bytes (+7) plus one over
its footprint, then scales by extractsmetal into unit +0x58. These observations
identify next reconstruction work, not verified complete resource formulas.

The metal-maker healthy lifecycle now matches 606 native snapshots with supplied
Create/Activate/Deactivate times and build-percent/health reads. The oracle uses
existing FactoryReference shading/caching callbacks; the simple solar fixture
alone could not execute this script. No VM changes were needed. The comparison
includes poses, threads, static variables, shading/caching and spin state.

Run native_solar_reference.py --unit armmakr and compare_native_solar.gd with
-- --armmakr. The native suite includes this check. Live metal-maker income,
energy starvation, extractor map data and original settlement timing remain
unfinished. Do not treat the script comparison as proof of economic behavior.

The isolated nonnegative upkeep branch at 0x4013eb..0x401480 now matches 32 native cases. It always adds upkeep to requested (+0xc0), adds it to accepted (+0xc4) only when debt (+0xc8) is nonpositive, and returns the productive flag. Values are float32. This helper is not yet live: settlement, cadence and debt creation must be mapped before its behavior can replace the provisional immediate-payment economy.

The aggregate allocation loop at 0x401a4d..0x401ab3 matches 350 native cases
covering both energy and metal lanes, zero totals, shortages, surpluses and
fractional float32 inputs. It spends available resources on old debt first,
records the paid fraction, then allocates the remainder to accepted work and
records that paid fraction. The oracle supplies the aggregate totals and starts
ECX at zero; the two lanes advance by four bytes. Godot resource_allocation.gd
reproduces these isolated calculations. The native verification suite runs the
oracle and comparison; the report is native-resource-allocation-validation.json.
This does not yet verify aggregation, storage clamping, per-unit debt updates or
settlement cadence, and the helper is not connected to the live economy.

Per-unit settlement at 0x401b42..0x401b9c matches 640 native cases across both
resource lanes with zero, partial and full payment fractions. New debt is
accepted minus paid accepted work, plus old debt minus paid old debt. Income
and requested usage roll into their previous-period fields; current income,
requested and accepted accumulators clear to zero. Products and subtraction
remain unrounded until the final float32 debt store, matching the tested x87
results. resource_allocation.gd now exposes this as settle(); the native suite
runs native_resource_debt.py and compare_native_resource_debt.gd. This check
supplies payment fractions directly and does not prove aggregation or cadence.

The economy deadline gate at 0x465077..0x465098 compares the player's unsigned
32-bit deadline (+0xf0) to the game tick (+0x38a47). When due, it advances the
old deadline by 30, wrapping at 32 bits. It advances only once per invocation,
including overdue calls. resource_schedule.gd matches 100 native boundary,
overdue and wraparound cases. This gate precedes the player/session checks
that decide whether to call resource settlement at 0x401360; the fixture does
not execute those eligibility branches. Static inspection also finds the
deadline initialized to the current game tick in 0x464700 and restored from
the save field UpdateTime. Those initialization/load paths are not yet
native-tested. Live economy still uses provisional per-tick income.

The combined maker fixture executes the entire original 0x401360 routine without
patching its economy instructions. A type-3 player bypasses the unrelated cloak
callback and avoids AI handicap branches. A completed generator and two active
makers run through 16 settlement periods for each of five starting stocks;
generation rises from 20 to 200 after eight periods, and one maker is switched
off for two recovery periods. All 80 snapshots match stock, aggregate income,
requested energy, metal income and each unit's energy debt. This includes storage
saturation and debt-gated production across consecutive updates. The Godot
settle_account helper aggregates ledgers in order, allocates available resources,
clamps storage and settles each ledger using the shared payment fractions.

Run native_maker_economy.py and compare_native_maker_economy.gd, also included in
the native suite. This materially extends isolated arithmetic checks but does
not cover construction accounting, extractor yield, AI handicap, cloak upkeep,
nonzero external ledgers or full scheduler eligibility. It is not yet live.
