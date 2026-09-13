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
