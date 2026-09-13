# Current task checkpoint

User goal: faithful Total Annihilation recreation first; graphics improvements later. User accepted our engine recommendation: Godot for presentation, independently reconstructed game logic. Keep the original GOG installation intact.

User asks to be told when Astra Light is sufficient, to reserve deeper reasoning for reverse engineering. Viewer UI, camera improvements, and routine fixes are now well-scoped enough for Light. Deciding archive precedence, reproducing the script VM, recovering simulation types/behavior, and resolving renderer discrepancies still call for deeper analysis. This is a task-scoping recommendation, not a claim that reverse engineering is finished.

## Completed

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

## Next engineering milestone

Movement foundation checkpoint: `godot/ground_motion.gd` implements native speed/vector and movement-rate callback primitives. `tools/native_movement_reference.py` executes original functions against synthetic engine records; `godot/compare_native_movement.gd` matches all 5,637 checks. Five native fixed-point parser assertions and 21 normal regression checks also pass. Full `tools/verify.ps1 -Native` passes, including the existing 464 COB snapshots. See `analysis/GROUND_MOVEMENT.md` for addresses, recovered layouts, oracle limits and remaining work. The viewer has not yet been connected to world movement. Ground steering (`0x0043cd20`), integration/collision (`0x0043d6d0`) and terrain sampling remain next. Selected TANKDS2 class constraints differ from Commander FBI constraints; trace their interaction rather than assuming which wins.

The Commander runtime milestone is complete within its documented subset. Next: trace original world movement and unit turn-rate/acceleration behavior, establish terrain-height coordinate mapping and collision/passability rules, and connect movement state to the existing StartMoving/StopMoving callbacks. Alternatively, resolve renderer projection and rotation order first for a closer visual baseline. Keep native-oracle tests as an executable behavioral reference; do not substitute approximate mechanics and label them faithful.

General archive lookup precedence remains unresolved; only its registration order was observed. The chosen Commander script is unaffected because all copies are identical. Do not infer stale BOS source solely from numeric differences: compiler unit scaling has not been reconstructed.

The user supplied GitHub repository `https://github.com/supertechieg/Total-Annihilation-Remake.git` and explicitly requested origin/main/push setup. Keep original binaries, extracted assets, tools, decompiled pseudocode, and raw extracted strings out of the source checkpoint (ignored locally).

A narrower Light task can improve the existing viewer or expose catalog filters without altering recovered format or simulation semantics.
