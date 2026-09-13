# Original unit and construction data

`tools/prepare_units.py` prepares a local bundle covering both factions from the declared archive profile `rev31.gp3`, `btdata.ccx`, `ccdata.ccx`, `totala1.hpi`, in that priority order. This is a provisional content selection, not a verified reconstruction of original archive precedence. Custom archives elsewhere in the installation are not silently mixed into this profile.

The current bundle contains 272 unit definitions with models and decoded COB programs, 193 weapon definitions, 450 model textures, 45 builder menus and 566 builder-to-unit relationships. Both Commanders have 19 options. No missing models, scripts, textures or build-menu units were found. These counts describe the selected profile, not a claim that every scenario-specific object or installed mod is covered.

The nested TDF parser keeps section scopes separate and normalizes names to lowercase. It supports comments and quoted values. Duplicate property replacement and duplicate section merging are provisional policies. `gamedata/sidedata.tdf` supplies base build relationships; selected `download/*.tdf` entries add options. Their original menu/button positions are recorded, but the loader currently appends unique options rather than reconstructing original button-conflict rules.

Every selected file records its archive, byte count, SHA-256 and candidate archives in ignored `local/unit-assets/provenance.json`. Unit definitions, geometry, decoded scripts, textures and weapon data remain in this ignored local bundle. None are committed to the source repository.

## Runtime integration

`unit_catalog.gd` loads and caches definitions, build relationships, models and programs. `unit_visuals.gd` compiles meshes by piece/material and shares mesh, material and texture resources across instances. Each instance retains separate piece nodes and transforms for its COB pose. The Commander viewer now uses this shared visual implementation.

All 272 models instantiate successfully in the headless renderer. The catalog verifier checks 8,924 references, including script-to-model piece names and all build options, with no failures. The existing real-map Commander movement and native-oracle checks still pass. A rendered Commander movement capture was inspected after integration. Instantiation and reference checks do not prove visual fidelity or complete script execution for every unit.

Known renderer limits remain: fan triangulation, UV orientation, rotation order and projection still require original-renderer comparisons. Three models (armch, armss, corss) have duplicate piece names; the current name binding selects the last occurrence. Original name-binding semantics need verification before those scripts can be claimed faithful. The reference checker deliberately tests that a name exists, not that this duplicate binding is correct.

## Reproduce

```powershell
python tools/prepare_units.py
.\tools\verify.ps1 -Native
```

`Run Viewer.cmd` now prepares both map and unit bundles automatically when missing. Normal verification includes six TDF parser tests, the catalog checks and all-model instantiation/resource-sharing checks. The result summary is `analysis/unit-catalog-validation.json`.

## Construction research handoff

The native unit parser at `0x0042bf40` stores build energy/metal costs as floats at definition offsets `+0x186/+0x18a`; BuildTime as integer at `+0x1ea`; WorkerTime as a 16-bit value at `+0x1fe`. EnergyMake, EnergyUse and MetalMake are floats at `+0x1c2/+0x1c6/+0x1ca`. These offsets identify the definitions, not yet the runtime accounting equations.

The selected Commander has WorkerTime=300, BuildDistance=60, EnergyMake=25 and MetalMake=1. The solar collector has BuildTime=2495, BuildCostMetal=145, BuildCostEnergy=760, EnergyMake=0 and **EnergyUse=-20**. Production cannot be inferred from EnergyMake alone. The extractor has ExtractsMetal=0.001 and EnergyUse=3; original map metal sampling and extraction accounting still need reconstruction.

Next work must connect build selection/placement, construction progress, resource consumption and completed structures to these definitions, and verify timing/accounting against the original engine. Merely loading a COB program does not establish that the current VM can run every opcode or satisfy every engine callback it needs.

## Larger armies and later graphics

The user reaffirmed complete gameplay first, graphical enhancements afterward, including better explosions and a classic presentation option. The user also requested reasonably larger armies, without committing to 10,000 units. Keep unit capacity configurable and avoid an architectural 250-unit cap. Benchmark progressively with combat, pathfinding and AI active; model-loading or idle-object tests cannot substantiate a playable-army limit. Shared visual resources are one foundation, not a performance guarantee.
