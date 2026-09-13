# First factory production loop

Arm Vehicle Plants and Kbot Labs accept their original six-entry build menus after completion. Factory scripts open the building and set construction stance before production begins. The host uses the shared native-compared construction primitive and original WorkerTime, BuildTime, costs and maximum health. Products consume resources incrementally, stop progressing when funds are insufficient, and retain their identity and paid progress. Clearing pending orders leaves the current product intact. The unit cap stalls new products without dropping queued orders.

QueryBuildInfo supplies the model piece used for the build position. Both enabled factory pads are directly under an unrotated base; their original local offsets and current COB translation supply the planar position. The finished unit receives a movement controller and an exit order. The next queued product waits until its predecessor's footprint clears the factory footprint. The factory deactivates when its queue and pad are empty, retaining its original delayed closing script.

The viewer selects completed factories to expose production controls, displays products during construction, and selects completed products for movement. All twelve original Arm ground factory products now execute their healthy scripts, including Kbot walking and stopping; see MOBILE_SCRIPTS.md. Construction Vehicles, Construction Kbots and Minelayers expose their original construction menus; see MOBILE_BUILDERS.md. No produced unit has combat yet.

## Verified behavior

- The existing native factory/rotation suite has 2,124 matching interpreter snapshots; see native-factory-validation.json. This establishes script execution with supplied healthy/clear-yard inputs, not production lifecycle timing.
- 36 factory host checks cover both factory types, rejection of unfinished factories and foreign menu units, opening readiness, completion/health, queried build position, stopped units blocking the pad, movement out of the yard, shortages/recovery, clearing pending orders, idle closing, and capacity stalls.
- The real Comet Catcher viewer integration builds a Vehicle Plant with the Commander, queues two Flash tanks through the production controls, waits for both to exit, selects one and moves it to a new destination. The normal verification suite passes, and a rendered capture was inspected.
- A further 73 checks exercise scripted production and exit for all twelve products, and a second real-map scenario produces and moves two Peewees from a Kbot Lab. Healthy product-script native playback matches 3,661 snapshots.

Run `.\tools\verify.ps1` for host/integration checks; add `-Native` to regenerate original interpreter comparisons. A visual demo uses Godot `--path godot -- --factory-demo --capture ABSOLUTE_PNG_PATH`.

## Provisional behavior and remaining work

Resource settlement still uses immediate payment, and work rate remains WorkerTime/30 per tick. Factory versus Commander resource arbitration is currently deterministic factory-first order, not recovered native scheduling. Original production callback timing is not yet reproduced.

`building_navigation.gd` overlays unrotated building footprints and the lowercase `o`, `c`, `y` yard characters used by these factories. The original parser at 0x0042cfc3 maps these to 0x2f, 0x2d, 0x29 respectively; original occupancy-bit behavior remains to be traced. The overlay treats `o` as solid, `c` as open with yard property 18 and `y` as open. Other characters conservatively block. Yard requests currently acknowledge immediately, so closing safety around unrelated occupants is unfinished. Building rotation, broader yard symbols, terrain/feature interactions and native occupancy comparison are still required.

Exit heading is provisionally 32768 toward the open end of these unrotated yards. The default exit point is 64 map units beyond the footprint. This avoids the observed collision caused by starting a vehicle facing into the back wall, but native production orientation/rally behavior still needs reconstruction. If terrain blocks exit, the product holds the queue and can receive a user move order; automatic recovery and dynamic unit-to-unit avoidance remain unfinished. Multiple units may overlap at the default exit point.

Navigation grids cache by unit type with its footprint/slope/water limits; building/yard changes rebuild their overlays. This is not a large-army performance claim. Each animated/render-rotated instance also retains a viewport. Exact renderer axes, scale, depth order, shading, construction effects and native pad/world projection remain unverified.

Next: remaining unit scripts, mobile-builder controls, Core factory coverage, native yard/lifecycle fidelity, weapons, projectiles and damage. The entire-game goal remains active.
