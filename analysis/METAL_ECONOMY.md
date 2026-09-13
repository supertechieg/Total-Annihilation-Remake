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
