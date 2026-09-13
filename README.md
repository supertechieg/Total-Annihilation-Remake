# Total Annihilation reconstruction

Goal: a faithful recreation using the installed game's data, followed by optional graphical improvements. The original executable is the behavioral reference. This repository contains analysis tooling and a playable development build with Commander movement, construction, solar production, and initial Arm factory queues. The complete replacement game remains under construction.

## Run the viewer

Double-click `Run Viewer.cmd`, or run:

```powershell
.\tools\run_viewer.ps1
```

The viewer displays Comet Catcher's original terrain and a controllable Arm Commander. Click terrain to issue a move order; the Commander turns, accelerates, follows a terrain route and brakes on arrival. Its original COB script drives walking, aiming, flashes, and construction poses. The runtime matches 464 recorded state snapshots from the original interpreter in an isolated x86 emulator; see [runtime evidence and limits](analysis/COB_VM.md).

| Control | Action |
| --- | --- |
| Drag / scroll | Pan / zoom |
| Click terrain | Move the selected mobile unit |
| Click completed factory | Select its production menu |
| Click produced unit | Select it for movement |
| Select Commander button | Return control to the Commander |
| Right-click / S | Stop and brake |
| Space | Start/stop original walk cycle, in place |
| 1 / 2 | Aim and show primary / D-gun flash |
| C | Clear target and restore pose |
| B | Enter/leave construction pose |
| Q / E | Rotate whole model |
| F / R | Center commander / reset zoom |

Original renderer fidelity and world simulation are still under reconstruction. Terrain routing and arrival handling are provisional. A first construction/resource loop is available; projectile and damage simulation are not yet implemented.

Choose a structure in the dropdown, press **Place selected structure**, and click nearby terrain. Right-click/S pauses Commander construction; click an unfinished structure to resume. Completed solar collectors generate energy and toggle on/off when clicked. Build an Arm Vehicle Plant or Kbot Lab, click it, choose a unit and press **Queue unit**. Completed units leave the pad and can be selected and moved. **Clear pending orders** retains the current unit. Combat and several resource sources remain unfinished; see [construction scope](analysis/CONSTRUCTION.md) and [factory scope and verification](analysis/FACTORIES.md).

Original speed caps, heading-to-velocity rounding, supplied-waypoint steering and movement-animation transitions match 6,837 native comparison checks. See [ground movement evidence and remaining work](analysis/GROUND_MOVEMENT.md) and [playable movement scope](analysis/PLAYABLE_MOVEMENT.md).

All twelve Arm ground factory products now execute their healthy original scripts, including Kbot walking and stopping. Product-script playback matches 3,661 native snapshots; [scope and verification](analysis/MOBILE_SCRIPTS.md).

Requires Godot 4 (tested on installed 4.6.2) and Python with Pillow for preparation. To recreate generated assets:

```powershell
python -m pip install -r requirements.txt
python tools\catalog_assets.py 'C:\Program Files (x86)\GOG Galaxy\Games\Total Annihilation'
python tools\prepare_viewer.py
python tools\test_assets.py
```

Run all normal checks with `.\tools\verify.ps1`. See [COB_VM.md](analysis/COB_VM.md) for the optional native-interpreter comparison.

Generated assets stay in Git-ignored `local/viewer-assets/` and are prepared from your installed game. Source selection, validation, and limitations are in [asset notes](analysis/ASSET_FORMATS.md); the next-work checkpoint is in [HANDOFF.md](HANDOFF.md).

The shared unit bundle in `local/unit-assets/` now supplies 272 units from both factions, their models/scripts, weapon definitions and build relationships. The launcher prepares it automatically; see [unit bundle scope and validation](analysis/UNIT_BUNDLE.md). Complete construction behavior and combat simulation are still being implemented.

## Installation under study

`C:\Program Files (x86)\GOG Galaxy\Games\Total Annihilation`

The inspector reads this directory without modifying it. Ghidra works on a local copy of `TotalA.exe`. Binaries, downloaded tools, Ghidra databases, and decompiled output stay under the Git-ignored `local/` directory.

## Reproduce the inventory

```powershell
python tools\inspect_install.py 'C:\Program Files (x86)\GOG Galaxy\Games\Total Annihilation'
```

Outputs in `analysis/`: file sizes and SHA-256 hashes, PE sections and imports, executable ASCII strings with file offsets, and a summary. String offsets are file offsets, not virtual addresses.

## Decompilation

Official tool: https://github.com/NationalSecurityAgency/ghidra

This workspace uses Ghidra 12.1.3, downloaded from its official release. Expected ZIP SHA-256:

`93a5d11a9ad510622acaaf908c556a7b9b764d338e78a7567f3689bf5081fd54`

With Ghidra unpacked in `local/tools/ghidra_12.1.3_PUBLIC` and a compatible JDK available:

```powershell
.\tools\decompile.ps1
```

The script creates `local/ghidra-projects/TotalAnnihilation.gpr` and exports C-like pseudocode, a function index, and string cross-references to `local/decompiled/`. It refuses to overwrite an existing project. Open that project with Ghidra to continue analysis and preserve annotations.

Decompiler output is an approximation with inferred types and generated names. It is not the original source and cannot simply be compiled into the game.

## Reconstruction milestones

1. **Executable baseline:** inventory, fingerprints, imports, decompiled function index; identify startup, data loading, simulation update, and rendering entry points.
2. **Asset access:** archive listing/extraction, explicit archive precedence, text unit/weapon definitions, models, textures, maps, and unit scripts. Verify against installed content.
3. **First visible slice:** load a real map and display an original unit with the original camera and palette behavior.
4. **Simulation slice:** selectable commander, movement and pathfinding, resource economy, construction, weapons, damage, and unit-script execution.
5. **Faithfulness:** controlled comparisons with the original game covering timing, movement, targeting, damage, resource accounting, fog of war, and save/load behavior. Multiplayer requires a separate determinism and protocol effort.
6. **Graphics improvements:** replace presentation incrementally while retaining the verified simulation and original presentation mode.

Existing reference candidate: [Robot War Engine](https://github.com/MHeasell/rwe), an open-source engine compatible with TA data. It has not yet been adopted as this project's foundation; assess functionality and license before integrating code.
