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

## Live integration

ConstructionWorld now uses these ledgers and settlement helpers. Passive income,
upkeep and accepted construction costs settle at ticks 0, 30, 60 and so on.
Construction accumulates requested/accepted work on the builder or factory;
unpaid debt gates later work. Completed Arm metal makers produce through the
verified upkeep gate and run their healthy Create/Activate/Deactivate scripts.
The existing structure toggle control accepts them as well as solar collectors.

compare_native_live_makers.gd drives actual World.step calls and real maker
scripts against all 80 native fixture snapshots, matching stock and unit debt
without script faults. Test definitions match the native fixture, including
its changing generator output. The full normal verification suite passes with
updated construction/factory tests for deferred acceptance, debt stalls and
recovery, and team isolation tests for the new settlement behavior.

This supersedes earlier notes that these helpers were not live. Fidelity gaps
remain: extractor map yield, wind/tidal income, cloak and AI handicap branches,
external ledgers, player-specific initial deadline phases, and original unit
update ordering. The current scenario shares a deadline starting at tick zero
and retains its configurable base storage. Construction math is native-tested,
but its complete scheduling interleave with the original economy is not yet
validated by a combined original construction trace.

## Extractor yield

extractor_yield.gd matches 160 cases from original setup 0x437840 and the original
map-cell lookup 0x481550. Supplied maps use 13-byte cells with metal at offset 7;
the lookup clips coordinates against game map dimensions. Each valid cell adds
its byte plus one to a wrapping 16-bit sum. The sum occupies the upper half of
a signed int32, is multiplied by float32 extractsmetal, then by exactly 1/65536,
and stored as float32. Thus sums above 32767 become negative; overflow cases
preserve this original behavior. Nonpositive extraction leaves prior yield
untouched. Tests cover homogeneous and varied bytes, edges, out-of-map and
empty footprints, positive/zero/negative scales and large-footprint overflow.

The fixture disables the SetSpeed callback by leaving the script pointer null;
otherwise the extractor and map-lookup routines execute unchanged. Original map
loading into metal bytes and script SetSpeed behavior still need verification
before this helper can provide live extractor income.

The full feature-metal pass at 0x422040 and original map lookup now match 48
cases in native_feature_metal.py against terrain_metal.feature_metal. Loaded
features with nonzero metal and indestructible (definition +0xff bit 1) overwrite
every valid cell in their footprint with the low byte of their metal value.
Anchors are scanned in map row order, so later anchors overwrite overlapping
earlier footprints. Zero-metal and destructible features leave the base intact.
The definition loader stores metal as an unsigned 16-bit integer converted to
float; the overlay truncates that to a byte. Tests cover these flags, clipping,
empty footprints, overlap and values through 65535. No native code is patched
by this fixture; loaded definitions and base cell bytes are supplied.

Static map-loader inspection distinguishes two attribute layouts: its older
8-byte cells provide metal at attribute offset 6, while the 4-byte layout starts
from the configured SurfaceMetal (or zero) before the feature pass. These loader
branches and the existing prepared map bundle still need to be connected and
checked; the overlay comparison alone does not prove map import fidelity.

prepare_map_metal.py now imports the 0x2000 Comet Catcher TNT feature table and
cell indices, resolves definitions through the existing declared content profile,
and applies the overlay to SurfaceMetal (zero when absent). It rejects unknown
or ambiguous definitions, invalid indices, overlapping placements and footprints
crossing the map boundary rather than guessing placement resolution. Comet has
81 accepted 3x3 metal deposits: 55 at byte value 223, 19 at 112, and 7 at 56.
There are 729 nonzero cells and no overlapping placements. metal.bin and metal.json
remain in ignored local/viewer-assets; metadata includes source hashes.

native_comet_metal.py executes the original full feature pass over these imported
placements and matches all 184320 cells. This verifies overlay application across
the whole map, while TNT decoding and definition loading remain reconstructed
outside the native routine. Both preparation and comparison are in the native
suite. The live world still needs to consume this bundle for extractor income.

## Live extractors

Arm extractor scripts now match 609 native snapshots, including Create, build
completion input, Activate/Deactivate and SetSpeed inputs 4, 896 and 452. The
comparison includes spin, shading, caching, threads, statics and poses. Healthy
extractor scripts are enabled in ConstructionWorld alongside metal makers.

The viewer loads metal.bin and rejects a missing/wrong-sized grid. The launcher
prepares that bundle when absent or when preparation is requested. Each extractor
computes footprint yield and supplies the corresponding signed sum to SetSpeed;
completed active extractors add yield only when the energy-debt upkeep gate
accepts their cost. The existing toggle control supports extractors. Installing
a terrain grid refreshes existing extractors as well as subsequently added ones.

The normal suite passes; test_live_extractor.gd adds 11 checks covering a 3x3
deposit, first-period deferred acceptance, starvation, debt repayment, recovery,
unfinished structures, grid size and on/off commands without script faults.
Placement uses the current world footprint-to-cell conversion, whose full native
alignment behavior remains unverified. Damaged scripts, terrain-metal changes
during play and the full original construction/callback ordering remain open.

The extractor cell-origin conversion now uses the original position-update rule
from 0x48a9f0: wrap signed32(position_raw - footprint_size * 0x80000 + 0x80000),
then arithmetic shift by 20. This corrects truncation at half-cell positions.
The helper matches 50 native position/size cases, including negative positions,
odd/even footprints and signed32 boundaries; spatial callbacks are stubbed.
The live extractor test now uses a half-cell position that distinguishes this
rule from the previous conversion and still passes all 11 checks. This verifies
the position-to-cell rule, not the complete building placement/snap policy.

## Removed-unit accounting

The maker oracle now optionally clears one maker's valid flag at period six.
The live comparison removes that maker through World.remove_unit and compares
balances and surviving-unit debt for all 80 snapshots. All match, including
starting-stock cases with about 30 and 45 energy debt on the removed maker.
The original leaves the invalid slot's ledger untouched and skips it during
aggregation/settlement; those costs are not transferred by settlement itself.
No live accounting change was needed. Static cleanup inspection also finds the
valid flag cleared near 0x486d24, but this test does not execute full destruction
callbacks and must not be treated as proof of every death/reclaim/cancel path.

## Economy display

The viewer now shows stock/capacity, last-period income and requested demand per
second, plus unpaid debt for each resource. Team-zero account reads preserve
these settlement statistics while still reflecting direct stock changes. The
live native-maker comparisons now also check exposed income and requested
energy for both ordinary and removed-maker traces (80 snapshots each); team
isolation remains 10/10. Debt shown is summed from the settled live-unit ledgers.
The display tooltip explains that unpaid costs can pause construction and metal
production. render_resource_display.gd captures the actual viewer with supplied
shortage values; the 1440x900 render was inspected and all six lines fit the
sidebar. The screenshot stays under ignored local/.

## Wind and tidal production

renewable_energy.gd matches 120 cases from the full original resource settlement
routine with supplied environment values. For active completed building fixtures,
positive extractsmetal or nonzero byte makesmetal suppresses the wind/tidal
branch. Otherwise positive windgenerator takes priority over positive
tidalgenerator. The selected definition multiplier times its environment value
is added to existing income, with a float32 store after the addition. Positive
energy debt does not suppress this renewable branch. Tests include inactive
units, both generator fields together, extractor/maker priority, negative wind
definition, fractional environment values and supplied debt.

The helper is not live yet: original wind evolution, environment import and
generator scripts still need connection. The native fixture uses player type 3
to bypass the cloak callback and does not exercise AI handicap branches.
