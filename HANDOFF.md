# Current task checkpoint

User goal: faithful Total Annihilation recreation first; graphics improvements later. User accepted our engine recommendation: Godot for presentation, independently reconstructed game logic. Keep the original GOG installation intact.

Use Light/low by default, including reverse engineering when it can be done reliably with more time. The user permits Medium only for a concrete problem that truly requires it, followed immediately by Light. No other modes or model substitutions are authorized. Do not escalate by broad task category.

## Completed

Weapon minimum barrel angle prepared: runtime.minimum_barrel_angle, default-11.25deg ->float32 -0.19634954631328583rad. Nativeweapon suite now821/821 (618earlier+203anglecases);6normal scalar tests. Unit runtime schema2, launcher auto-upgrades, catalog rejects stale data. Bundle regenerated272units193weapons. Next: native muzzle/AimFrom world transforms and cannon lifetime/collision/splash, then integrate Raider firing. See WEAPON_SCALARS.md.

Cannon controller offset source recovered: initialization0x49e070 queries muzzle and AimFrom world coordinates; stored controller+0x10 is trunc(signed32(muzzleZ-aimZ)*1.25), NOT merely elapsed time. ballistic_launch.initial_offset matches300 native block cases; total launch comparison1300, normal launch checks14. Native piece-world transform still unverified. Aim minimum is weapon minbarrelangle default-11.25 degrees, scaled by0.017453292519943278 into float32 atweapon+c8; loader conversion inspection only. See updated BALLISTICS.md. Next connect query origins with verified transforms, prepare minimum angle, resolve lifetime/collision/splash for Raider.

Map gravity: native_map_gravity.py matches96 loader cases; map_environment.py recovers default/override and x87 scale. Comet Catcher is gravity60 ->raw4369, winds10..15 (not default8155 used by isolated fixtures). prepare_viewer now reads OTA and writes scene.environment +environment_version1; launcher upgrades older bundles. Six normal tests. See analysis/BALLISTICS.md and native-map-gravity-validation.json. Remaining integration: controller accumulator/min-angle evolution, wind initialization/scheduling, lifetime/collision/splash before armed Raider.

Wind update: wind_state.gd matches 600 native 0x490c40 cases including both original RNG final states, timer gating, strength/heading, quantized X/Z drift and float32 ratio; 8 normal checks. Oracle replaces only CRT thread-storage lookup, not randomness. See analysis/WIND.md and native-wind-validation.json. Not world-scheduled yet: initial normalization, seeds, Y drift initialization and shared random consumers remain. Ballistic controller accumulator/map gravity/lifetime/splash still block faithful armed Raider integration, not work overall.

Ballistic launch velocity: ballistic_launch.gd matches 1,000 native cases at 0x49ce4f..0x49cecc, using original integer trig plus gravity * unsigned(controller+0x10)/speed vertical correction. Six normal native fixtures. See analysis/BALLISTICS.md and native-ballistic-launch-validation.json. Controller accumulator evolution is still untraced; do not assume always zero. Drift writer located at wind update0x490c40: X/Z=-2*sin/cos(wind heading+0x37ed8,strength+0x37eda). Next recover controller state/map gravity/wind and lifetime/splash, then integrate armed Raider.

Ballistic aiming: ballistic_aim.gd matches 1,236 unmodified native 0x49a890 calls (494 accepted), including adjacent raw distances at maximum reach. Source-minus-target coordinates, positive speed/gravity, minimum angle; returns unsigned COB pitch or 0x8000 failure. Nine normal native-derived fixtures. See analysis/BALLISTICS.md and native-ballistic-aim-validation.json. Next remains launch 0x49cde0, map gravity/drift, lifetime and splash before armed Raider integration. Current binary64 reconstruction is verified for tested cases, not a general x87 precision proof.

Ballistic primitive: 1,120 native cases match the original live ballistic update (1,000 varied inputs +120-step arc). New ballistic_motion.gd moves by velocity plus supplied game drift before subtracting gravity; signed32 wrap preserved. Five normal checks, optional native oracle/comparator in verify.ps1. See analysis/BALLISTICS.md for addresses and boundaries. Not connected to world firing yet. Next trace aim 0x49a890, launch 0x49cde0, map gravity loading and drift derivation, then lifetime/collision/splash. Do not reuse the EMG path-distance lifetime for shells without native evidence.

Core Raider firing prerequisite: 325 native interpreter snapshots match for healthy Create/aim/query/fire/recoil plus two HitByWeapon rocking callbacks. `native_firing_reference.py --unit corraid` writes local/firing/corraid; `compare_native_firing.gd -- --corraid` compares it. Normal weapon-cycle checks now 18, including sustained Raider single-shot events. Raider added to healthy SCRIPTED_UNITS so practice-target muzzle visibility/poses are script-driven. No Raider world firing yet: CORE_LIGHTCANNON is ballistic=1, range240, damage50, AoE32, speed raw371370 and reload45 ticks. Next: reconstruct ballistic trajectories/aiming and splash before armed Raider opponent; do not silently use straight EMG geometry. See analysis/FIRING_CYCLE.md and native-raider-firing-validation.json.

Latest playable combat checkpoint: a selected factory-produced Flash can attack a stationary Core Raider practice target using queried muzzle poses, EMG burst callbacks, integer projectile integration, provisional swept sphere hits, health and removal. Use Add practice target, then click the red-ringed target; Stop/move cancels. 18 combat host checks and --verify-combat pass. --combat-demo renders a live firing scene. See analysis/COMBAT.md for full limits: no spray, splash, armor, damage COB callbacks, native collision fidelity, original death effects or AI yet. This supersedes older notes saying combat is not connected. Next: enemy behavior plus missing weapon/damage fidelity and Core coverage.

Firing prerequisite: Flash QueryPrimary/FirePrimary overlap and recoil match 323 native snapshots, including actual query output locals. First three supplied muzzle queries are 0,0,1; do not hard-code alternation. `weapon_cycle.gd` emits script-queried shot events with provisional burst/reload timing and re-aims after idle restoration/permission pauses. Fourteen host checks pass. It is not yet wired to the world; next is projectile spawn transforms/spread, collision and damage. See analysis/FIRING_CYCLE.md.

Combat prerequisite: exact loader conversions for weapon speed, reload ticks and burst interval are now prepared into each weapon's local `runtime` data. 618 native cases match; see analysis/WEAPON_SCALARS.md. x87 precision matters (.3 seconds => 8 ticks; EMG speed 300 => raw 655359/tick). `unit_catalog.weapon(name)` exposes these values; launcher upgrades old bundles. Next combat work is firing callback/burst scheduling, projectiles, hits and damage; no combat is playable yet.

Mobile-builder extension: Arm Construction Vehicles, Construction Kbots and Minelayers now expose original menus and independent construction jobs. StartBuilding/readiness/StopBuilding, range, pause/resume and move cancellation are integrated. 48 host checks and a real-map factory-produced Construction Vehicle building solar pass; see analysis/MOBILE_BUILDERS.md. Normal verifier includes --builder-demo. Older notes saying mobile-builder commands are missing are superseded. Combat/opponents and Core coverage remain the next major gameplay work.

Latest extension: all twelve Arm Vehicle Plant/Kbot Lab products execute healthy original COB scripts. Native playback matches 3,661 snapshots; 73 host checks cover production, animation and exit for every product. Odd-sized footprint alignment in the yard overlay was fixed to agree with terrain_navigation. Both real-map factory demos pass. See analysis/MOBILE_SCRIPTS.md; this supersedes older notes about static Kbot poses. Next major gameplay work remains mobile-builder controls, combat and opponents, alongside Core coverage and fidelity work.

- Installation inventory and PE inspection in `analysis/`.
- Ghidra 12.1.3 project at `local/ghidra-projects/TotalAnnihilation.gpr`.
- 2,640 functions decompiled; one failed at `0x004e5392`. Approximate output, not buildable source.
- Archive directory catalog, HAPI extraction, selected TNT/3DO/GAF conversion.
- Working Godot viewer: Comet Catcher and textured Arm Commander, now driven by original COB bytecode.
- COB decoder and disassembler; all four installed Commander script variants are identical, no loose override.
- Scene-independent GDScript runtime implementing the Commander-used instruction subset, eight slots, 32-word stacks, 30 Hz timing, child-call waits, signals, and integer motion.
- 58 runtime checks, 14 Python parser tests, and viewer integration checks pass.
- Stronger test: isolated Unicorn execution of original x86 interpreter matches all 464 state snapshots over 450 ticks. Reproducible with `tools/verify.ps1 -Native`; see `analysis/COB_VM.md` and `analysis/native-cob-validation.json`.
- Native comparison found and corrected the already-at-target MOVE velocity edge case.
- `local/commander-walk.mp4` captures 60 rendered frames of script-driven motion.
- Validation and known limitations: `analysis/ASSET_FORMATS.md`.

## Run

Double-click `Run Viewer.cmd`, or run `tools/run_viewer.ps1`.

Prepare again: `python tools/prepare_viewer.py`.

Normal checks: `tools/verify.ps1` (Python parser tests, runtime checks, viewer checks).

Godot checks: `Godot_v4.6.2-stable_win64_console.exe --headless --path godot -- --verify`.

Screenshot: run Godot with `--path godot -- --capture ABSOLUTE_PNG_PATH` without `--headless`.

## Active goal and next engineering milestone

The user explicitly set the active goal to a playable version of the entire Total Annihilation game. A Codex goal is active; do not mark it complete at intermediate checkpoints. Continue autonomously through playable systems and preserve the fidelity evidence/limitations distinction. No token budget was requested. No subagents were authorized.

Commander map movement is now available: click terrain to move, right-click/S to stop. Native ground steering (0x0043cd20) matches 1,200 additional supplied-waypoint cases, bringing movement comparison to 6,837 checks. `terrain_navigation.gd` supplies a provisional footprint-aware A* route; `mobile_unit.gd` integrates this with the original script. Twelve navigation checks and a real-map viewer integration run pass; actual Commander goes from (3072,3840) to (3199.673,3744.345), stops and settles its original pose. `tools/verify.ps1 -Native` passes all existing checks too. See `analysis/PLAYABLE_MOVEMENT.md` and `analysis/GROUND_MOVEMENT.md`.

Current next work: broader unit script coverage and mobile builders, Core factories, weapons/projectiles/damage and opponents. Work toward an actual playable skirmish loop while continuing native terrain/collision research. Do not describe the provisional A* and sampled height as faithful original navigation. Pitch remains zero; map feature collision, class-vs-FBI rules, terrain projection and full economy fidelity remain unfinished.

Update: the original-data bundle and shared visuals are now implemented. `tools/prepare_units.py` prepares 272 units, 193 weapons, 450 textures, 45 builder menus, 566 build relationships. Nested `tools/tdf.py` parses actual data; `unit_catalog.gd` caches it; `unit_visuals.gd` shares GPU mesh/material/texture resources while keeping independent poses. Viewer uses this renderer. All 272 models instantiate; 8,924 catalog checks and full native suite pass. See `analysis/UNIT_BUNDLE.md` for source-selection limits and construction-field offsets. Next concrete work is construction placement/progress/resource accounting. Duplicate model names in armch/armss/corss need original binding verification. Programs decode but VM engine-callback/opcode support for all units is not complete.

User refinements: full gameplay rebuild first, graphical improvements afterward, specifically improved explosions while retaining classic presentation. Raise unit capacity reasonably and make it configurable; user explicitly softened 10,000 into a benchmark-driven target. Do not promise a numeric playable limit without full combat/pathfinding/AI load tests. Current shared meshes are a foundation, not a performance benchmark.

Construction update: first playable loop is now in `construction_world.gd` and viewer: dropdown placement, costs, partial progress, stop/resume, completion, completed-unit production/storage. Original positive-work routine 0041ba60 and request routine 004011c0 match 1,000 native cases through `construction_math.gd`; use float32-bit comparisons (JSON decimal formatting caused false mismatches initially). Host work timing, immediate spending, placement/range and production are provisional. Fifteen host tests and real-map solar completion pass. Building models remain static without their COB programs, so solar panels do not animate open. See `analysis/CONSTRUCTION.md`. Next: building script callbacks/activation, resource settlement, factory production, selection and combat.

Strict reasoning preference: user authorizes ONLY Light/low and Medium. Evaluate every step; use Light even if slower. Medium only for a concrete difficult reasoning problem Light cannot reliably resolve, then return immediately to Light. Switching via `mcp__codex_app__send_message_to_thread` to this same task with `thinking` low/medium was tested; user confirmed the UI switch worked. Current requested setting is Light. Do not repeat the test or queue recursive switching messages. Announce actual necessary switches briefly. No other reasoning modes or model substitutions are authorized.

Native movement oracle stubs route-provider virtual calls, not the steering routine. Initialize x87 to FINIT state; Unicorn defaults caused native CRT exception paths before this was corrected. `capstone==5.0.7` is available in ignored local/python-deps for disassembly, but not needed to run the oracle. Route source has three points: previous, target, final. Exact path-provider meanings/selection remain to be traced. Disassembly excerpt is ignored `local/movement/ground-steering.asm`.

General archive lookup precedence remains unresolved; only its registration order was observed. The chosen Commander script is unaffected because all copies are identical. Do not infer stale BOS source solely from numeric differences: compiler unit scaling has not been reconstructed.

The user supplied GitHub repository `https://github.com/supertechieg/Total-Annihilation-Remake.git` and explicitly requested origin/main/push setup. Keep original binaries, extracted assets, tools, decompiled pseudocode, and raw extracted strings out of the source checkpoint (ignored locally).

Latest checkpoint: playable Arm factory queues, pad production, automatic exit and selected-unit movement are now implemented. See `analysis/FACTORIES.md` for complete scope and remaining fidelity gaps. The normal suite includes 36 factory host checks plus a real-map Commander-built Vehicle Plant producing two Flash tanks and moving a selected tank. Solar animation has 606 native snapshots; Arm factory/rotation has 2,124. The host uses provisional yard overlays, immediate property-18 readback, a fixed unrotated exit direction and cached per-type navigation. Dynamic unit avoidance, other product animations, mobile-builder controls and actual combat remain unfinished. The older construction/bundle paragraphs above describe prior checkpoints; this paragraph and current source/tests supersede their outstanding-work lists.
