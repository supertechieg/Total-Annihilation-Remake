param([switch]$Native)
$ErrorActionPreference = 'Stop'
$workspacePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$godotCommand = Get-Command godot -ErrorAction SilentlyContinue
$godotPath = if ($godotCommand) { $godotCommand.Source } else {
    (Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\Godot*_win64_console.exe" | Select-Object -First 1).FullName
}
if (-not $godotPath) { throw 'Godot 4 is required. Add godot to PATH.' }
Push-Location $workspacePath
try {
    & $godotPath --headless --path godot --script res://test_movement_classes.gd
    if ($LASTEXITCODE -ne 0) { throw 'Movement class integration failed' }
    & $godotPath --headless --path godot --script res://test_live_tidal.gd
    if ($LASTEXITCODE -ne 0) { throw 'Live tidal generation failed' }
    & $godotPath --headless --path godot --script res://test_live_wind.gd
    if ($LASTEXITCODE -ne 0) { throw 'Live wind generation failed' }
    & $godotPath --headless --path godot --script res://test_opponent_metal_expansion.gd
    if ($LASTEXITCODE -ne 0) { throw 'Opponent metal expansion failed' }
    & $godotPath --headless --path godot --script res://test_opponent_power.gd
    if ($LASTEXITCODE -ne 0) { throw 'Opponent power expansion failed' }
    & $godotPath --headless --path godot --script res://test_opponent_extractor.gd
    if ($LASTEXITCODE -ne 0) { throw 'Opponent extractor expansion failed' }
    & $godotPath --headless --path godot --script res://test_live_extractor.gd
    if ($LASTEXITCODE -ne 0) { throw 'Live extractor checks failed' }
    & $godotPath --headless --path godot --quit-after 2 --script res://test_live_core_resources.gd
    if ($LASTEXITCODE -ne 0) { throw 'Live Core resource building checks failed' }
    & $godotPath --headless --path godot --script res://test_weapon_effects.gd
    if ($LASTEXITCODE -ne 0) { throw 'Weapon effect checks failed; prepare effects with tools/prepare_weapon_effects.py' }
    & $godotPath --headless --path godot --script res://test_weapon_audio.gd
    if ($LASTEXITCODE -ne 0) { throw 'Weapon audio playback checks failed; prepare sounds with tools/prepare_weapon_sounds.py' }
    & $godotPath --headless --path godot --script res://test_team_economy.gd
    if ($LASTEXITCODE -ne 0) { throw 'Team economy checks failed' }
    & $godotPath --headless --path godot --script res://test_opponent.gd
    if ($LASTEXITCODE -ne 0) { throw 'Opponent production/combat checks failed' }
    & $godotPath --headless --path godot --script res://test_opponent_base.gd
    if ($LASTEXITCODE -ne 0) { throw 'Opponent base-building checks failed' }
    & $godotPath --headless --path godot --script res://test_opponent_base.gd -- --core
    if ($LASTEXITCODE -ne 0) { throw 'Core opponent base-building checks failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-opponent
    if ($LASTEXITCODE -ne 0) { throw 'Opponent viewer scenario failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-opponent --faction core
    if ($LASTEXITCODE -ne 0) { throw 'Core player versus Arm opponent scenario failed' }
    & $godotPath --headless --path godot --script res://test_scenario_result.gd
    if ($LASTEXITCODE -ne 0) { throw 'Scenario result checks failed' }
    & $godotPath --headless --path godot --quit-after 90 --script res://test_faction_selection.gd
    if ($LASTEXITCODE -ne 0) { throw 'Viewer faction selection failed' }
    & $godotPath --headless --path godot --script res://test_team_unit_limit.gd
    if ($LASTEXITCODE -ne 0) { throw 'Team unit limit checks failed' }
    python tools\test_assets.py
    if ($LASTEXITCODE -ne 0) { throw 'Asset parser tests failed' }
    python tools\test_cob.py
    if ($LASTEXITCODE -ne 0) { throw 'COB parser tests failed' }
    python tools\test_tdf.py
    if ($LASTEXITCODE -ne 0) { throw 'TDF parser tests failed' }
    python tools\test_weapon_math.py
    if ($LASTEXITCODE -ne 0) { throw 'Weapon scalar checks failed' }
    python tools\test_map_environment.py
    if ($LASTEXITCODE -ne 0) { throw 'Map environment checks failed' }
    python tools\test_feature_blocking.py
    if ($LASTEXITCODE -ne 0) { throw 'Feature blocking grid checks failed' }
    & $godotPath --headless --path godot --script res://test_unit_catalog.gd
    if ($LASTEXITCODE -ne 0) { throw 'Unit catalog checks failed' }
    & $godotPath --headless --path godot --script res://test_unit_visuals.gd
    if ($LASTEXITCODE -ne 0) { throw 'Unit visual checks failed' }
    & $godotPath --headless --path godot --script res://test_cob_vm.gd
    if ($LASTEXITCODE -ne 0) { throw 'COB runtime checks failed' }
    & $godotPath --headless --path godot --script res://test_ground_motion.gd
    if ($LASTEXITCODE -ne 0) { throw 'Ground motion checks failed' }
    & $godotPath --headless --path godot --script res://test_navigation.gd
    if ($LASTEXITCODE -ne 0) { throw 'Terrain navigation checks failed' }
    & $godotPath --headless --path godot --script res://test_construction_world.gd
    if ($LASTEXITCODE -ne 0) { throw 'Construction checks failed' }
    & $godotPath --headless --path godot --script res://test_factory_world.gd
    if ($LASTEXITCODE -ne 0) { throw 'Factory production checks failed' }
    & $godotPath --headless --path godot --script res://test_produced_scripts.gd
    if ($LASTEXITCODE -ne 0) { throw 'Produced unit script checks failed' }
    & $godotPath --headless --path godot --script res://test_mobile_builders.gd
    if ($LASTEXITCODE -ne 0) { throw 'Mobile builder checks failed' }
    & $godotPath --headless --path godot --script res://test_weapon_cycle.gd
    if ($LASTEXITCODE -ne 0) { throw 'Weapon cycle checks failed' }
    & $godotPath --headless --path godot --script res://test_weapon_queries.gd
    if ($LASTEXITCODE -ne 0) { throw 'Weapon piece query checks failed' }
    & $godotPath --headless --path godot --script res://test_ballistic_motion.gd
    if ($LASTEXITCODE -ne 0) { throw 'Ballistic motion checks failed' }
    & $godotPath --headless --path godot --script res://test_ballistic_aim.gd
    if ($LASTEXITCODE -ne 0) { throw 'Ballistic aim checks failed' }
    & $godotPath --headless --path godot --script res://test_ballistic_launch.gd
    if ($LASTEXITCODE -ne 0) { throw 'Ballistic launch checks failed' }
    & $godotPath --headless --path godot --script res://test_wind_state.gd
    if ($LASTEXITCODE -ne 0) { throw 'Wind state checks failed' }
    & $godotPath --headless --path godot --script res://test_piece_origin.gd
    if ($LASTEXITCODE -ne 0) { throw 'Piece origin checks failed' }
    & $godotPath --headless --path godot --script res://test_splash_damage.gd
    if ($LASTEXITCODE -ne 0) { throw 'Splash falloff checks failed' }
    & $godotPath --headless --path godot --script res://test_unit_bounds.gd
    if ($LASTEXITCODE -ne 0) { throw 'Unit bounds checks failed' }
    & $godotPath --headless --path godot --script res://test_projectile_collision.gd
    if ($LASTEXITCODE -ne 0) { throw 'Projectile collision checks failed' }
    & $godotPath --headless --path godot --script res://test_collision_grid.gd
    if ($LASTEXITCODE -ne 0) { throw 'Collision grid checks failed' }
    & $godotPath --headless --path godot --script res://test_world_collision.gd
    if ($LASTEXITCODE -ne 0) { throw 'World collision lifecycle checks failed' }
    & $godotPath --headless --path godot --script res://test_combat_world.gd
    if ($LASTEXITCODE -ne 0) { throw 'Combat host checks failed' }
    & $godotPath --headless --path godot --script res://test_burst_combat.gd
    if ($LASTEXITCODE -ne 0) { throw 'Burst combat checks failed' }
    & $godotPath --headless --path godot --script res://test_reload_combat.gd
    if ($LASTEXITCODE -ne 0) { throw 'Reload combat checks failed' }
    & $godotPath --headless --path godot --script res://test_cannon_combat.gd
    if ($LASTEXITCODE -ne 0) { throw 'Cannon combat checks failed' }
    & $godotPath --headless --path godot --script res://test_firing_spread.gd
    if ($LASTEXITCODE -ne 0) { throw 'Firing spread checks failed' }
    & $godotPath --headless --path godot --script res://test_commander_combat.gd
    if ($LASTEXITCODE -ne 0) { throw 'Commander combat checks failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-commander-combat
    if ($LASTEXITCODE -ne 0) { throw 'Arm Commander real-map combat failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-commander-combat --faction core
    if ($LASTEXITCODE -ne 0) { throw 'Core Commander real-map combat failed' }
    & $godotPath --headless --path godot --script res://test_dgun.gd
    if ($LASTEXITCODE -ne 0) { throw 'D-gun checks failed' }
    & $godotPath --headless --path godot --script res://test_unit_death.gd
    if ($LASTEXITCODE -ne 0) { throw 'Unit death checks failed' }
    & $godotPath --headless --path godot --script res://test_wreckage.gd
    if ($LASTEXITCODE -ne 0) { throw 'Wreckage checks failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-wreckage
    if ($LASTEXITCODE -ne 0) { throw 'Arm real-map wreckage failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-wreckage --faction core
    if ($LASTEXITCODE -ne 0) { throw 'Core real-map wreckage failed' }
    & $godotPath --headless --path godot --script res://test_reclaim.gd
    if ($LASTEXITCODE -ne 0) { throw 'Reclaim checks failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-reclaim
    if ($LASTEXITCODE -ne 0) { throw 'Arm real-map reclaim failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-reclaim --faction core
    if ($LASTEXITCODE -ne 0) { throw 'Core real-map reclaim failed' }
    & $godotPath --headless --path godot --script res://test_feature_damage.gd
    if ($LASTEXITCODE -ne 0) { throw 'Feature damage checks failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-feature-damage
    if ($LASTEXITCODE -ne 0) { throw 'Arm real-map feature damage failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-feature-damage --faction core
    if ($LASTEXITCODE -ne 0) { throw 'Core real-map feature damage failed' }
    python tools\test_map_feature_loader.py
    if ($LASTEXITCODE -ne 0) { throw 'Map feature loader tests failed' }
    & $godotPath --headless --path godot --script res://test_maps.gd
    if ($LASTEXITCODE -ne 0) { throw 'Skirmish map load checks failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --map sherwood --verify-commander-combat
    if ($LASTEXITCODE -ne 0) { throw 'Sherwood viewer run failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --map the-cold-place --faction core --verify-commander-combat
    if ($LASTEXITCODE -ne 0) { throw 'The Cold Place Core viewer run failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-build-menu
    if ($LASTEXITCODE -ne 0) { throw 'Arm build menu failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-build-menu --faction core
    if ($LASTEXITCODE -ne 0) { throw 'Core build menu failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-squads
    if ($LASTEXITCODE -ne 0) { throw 'Arm squads failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-squads --faction core
    if ($LASTEXITCODE -ne 0) { throw 'Core squads failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-projection
    if ($LASTEXITCODE -ne 0) { throw 'Arm projection failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --map sherwood --faction core --verify-projection
    if ($LASTEXITCODE -ne 0) { throw 'Core projection failed' }
    & $godotPath --headless --path godot --script res://test_minimap.gd
    if ($LASTEXITCODE -ne 0) { throw 'Minimap checks failed' }
    & $godotPath --headless --path godot --script res://test_feature_animation.gd
    if ($LASTEXITCODE -ne 0) { throw 'Feature animation checks failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --map sherwood --verify-map-features
    if ($LASTEXITCODE -ne 0) { throw 'Sherwood map feature sprites failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --map acid-pools --faction core --verify-map-features --require-animation
    if ($LASTEXITCODE -ne 0) { throw 'Acid Pools animated map features failed' }
    & $godotPath --headless --path godot --script res://test_damage_notify.gd
    if ($LASTEXITCODE -ne 0) { throw 'Damage notification checks failed' }
    & $godotPath --headless --path godot --script res://test_self_destruct.gd
    if ($LASTEXITCODE -ne 0) { throw 'Self-destruct checks failed' }
    & $godotPath --headless --path godot --script res://test_ground_attack.gd
    if ($LASTEXITCODE -ne 0) { throw 'Ground attack checks failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-self-destruct
    if ($LASTEXITCODE -ne 0) { throw 'Arm real-map self-destruct failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-self-destruct --faction core
    if ($LASTEXITCODE -ne 0) { throw 'Core real-map self-destruct failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-ground-attack
    if ($LASTEXITCODE -ne 0) { throw 'Arm real-map ground attack failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-ground-attack --faction core
    if ($LASTEXITCODE -ne 0) { throw 'Core real-map ground attack failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --map sherwood --verify-skirmish-start
    if ($LASTEXITCODE -ne 0) { throw 'Sherwood skirmish start failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --map the-cold-place --faction core --verify-skirmish-start
    if ($LASTEXITCODE -ne 0) { throw 'The Cold Place skirmish start failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-dgun
    if ($LASTEXITCODE -ne 0) { throw 'Arm Commander real-map D-gun failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-dgun --faction core
    if ($LASTEXITCODE -ne 0) { throw 'Core Commander real-map D-gun failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-group-orders
    if ($LASTEXITCODE -ne 0) { throw 'Arm group selection and orders failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-group-orders --faction core
    if ($LASTEXITCODE -ne 0) { throw 'Core group selection and orders failed' }
    & $godotPath --headless --path godot --script res://test_guard_combat.gd
    if ($LASTEXITCODE -ne 0) { throw 'Guard combat checks failed' }
    & $godotPath --headless --path godot --script res://test_attack_orders.gd
    if ($LASTEXITCODE -ne 0) { throw 'Player attack order checks failed' }
    & $godotPath --headless --path godot --script res://test_weapon_damage.gd
    if ($LASTEXITCODE -ne 0) { throw 'Weapon damage checks failed' }
    & $godotPath --headless --path godot -- --verify
    if ($LASTEXITCODE -ne 0) { throw 'Viewer checks failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --kbot-demo
    if ($LASTEXITCODE -ne 0) { throw 'Real-map Kbot production and movement failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --core-factory-demo
    if ($LASTEXITCODE -ne 0) { throw 'Real-map Core factory production failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --builder-demo
    if ($LASTEXITCODE -ne 0) { throw 'Real-map mobile builder construction failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --core-builder-demo
    if ($LASTEXITCODE -ne 0) { throw 'Real-map Core mobile builder construction failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-combat
    if ($LASTEXITCODE -ne 0) { throw 'Real-map Flash combat failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-duel
    if ($LASTEXITCODE -ne 0) { throw 'Real-map armed tank duel failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-stumpy
    if ($LASTEXITCODE -ne 0) { throw 'Stumpy duel failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-hammer
    if ($LASTEXITCODE -ne 0) { throw 'Real-map Hammer duel failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-peewee
    if ($LASTEXITCODE -ne 0) { throw 'Real-map Peewee duel failed' }
    & $godotPath --headless --path godot --script res://test_rocket_combat.gd
    if ($LASTEXITCODE -ne 0) { throw 'Rocket combat failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-rocko
    if ($LASTEXITCODE -ne 0) { throw 'Rocko factory duel failed' }
    & $godotPath --headless --path godot --script res://test_cannon_combat.gd -- --armwar
    if ($LASTEXITCODE -ne 0) { throw 'Warrior cannon combat failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-warrior
    if ($LASTEXITCODE -ne 0) { throw 'Warrior factory duel failed' }
    foreach ($missileUnit in @('armsam', 'armjeth')) {
        & $godotPath --headless --path godot --quit-after 2 -- "--verify-$missileUnit"
        if ($LASTEXITCODE -ne 0) { throw "$missileUnit factory duel failed" }
    }
    & $godotPath --headless --path godot --script res://test_cannon_combat.gd -- --corlevlr
    if ($LASTEXITCODE -ne 0) { throw 'Leveler cannon combat failed' }
    foreach ($laserUnit in @('armfav', 'corfav', 'corgator', 'corak')) {
        & $godotPath --headless --path godot --script res://test_beam_combat.gd -- "--$laserUnit"
        if ($LASTEXITCODE -ne 0) { throw "$laserUnit beam combat failed" }
    }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-armfav
    if ($LASTEXITCODE -ne 0) { throw 'Jeffy laser factory duel failed' }
    foreach ($coreUnit in @('corthud', 'corlevlr', 'corstorm', 'cormist', 'corcrash', 'corfav', 'corgator', 'corak')) {
        & $godotPath --headless --path godot --quit-after 2 -- "--verify-$coreUnit"
        if ($LASTEXITCODE -ne 0) { throw "$coreUnit Core factory duel failed" }
    }
    if ($Native) {
        python tools\native_map_tidal.py
        if ($LASTEXITCODE -ne 0) { throw 'Original tidal environment differs' }
        python tools\native_placement_defaults.py
        if ($LASTEXITCODE -ne 0) { throw 'Original placement defaults differ' }
        python tools\native_movement_definition.py
        if ($LASTEXITCODE -ne 0) { throw 'Original movement definition differs' }
        python tools\native_terrain_limits.py
        if ($LASTEXITCODE -ne 0) { throw 'Original terrain limits trace failed' }
        python tools\native_terrain_heights.py
        if ($LASTEXITCODE -ne 0) { throw 'Original terrain height preparation differs' }
        python tools\native_footprint_passability.py
        if ($LASTEXITCODE -ne 0) { throw 'Original footprint passability differs' }
        & $godotPath --headless --path godot --script res://compare_native_footprint_passability.gd
        if ($LASTEXITCODE -ne 0) { throw 'Live footprint passability differs' }
        & $godotPath --headless --path godot --script res://compare_native_terrain_heights.gd
        if ($LASTEXITCODE -ne 0) { throw 'Live terrain height preparation differs' }
        & $godotPath --headless --path godot --script res://compare_native_terrain_limits.gd
        if ($LASTEXITCODE -ne 0) { throw 'Original terrain limits differ' }
        foreach ($generator in @('armwin', 'armtide')) {
            python tools\native_solar_reference.py --unit $generator
            if ($LASTEXITCODE -ne 0) { throw 'Original generator script failed' }
            & $godotPath --headless --path godot --script res://compare_native_solar.gd -- "--$generator"
            if ($LASTEXITCODE -ne 0) { throw 'Generator script differs from original' }
        }
        python tools\native_renewable_energy.py
        if ($LASTEXITCODE -ne 0) { throw 'Original renewable energy failed' }
        & $godotPath --headless --path godot --script res://compare_native_renewable_energy.gd
        if ($LASTEXITCODE -ne 0) { throw 'Renewable energy differs from original' }
        python tools\native_maker_economy.py --remove-maker
        if ($LASTEXITCODE -ne 0) { throw 'Original removed-maker settlement failed' }
        & $godotPath --headless --path godot --script res://compare_native_live_makers.gd -- --remove-maker
        if ($LASTEXITCODE -ne 0) { throw 'Removed-maker settlement differs from original' }
        python tools\native_footprint_origin.py
        if ($LASTEXITCODE -ne 0) { throw 'Original footprint origin failed' }
        & $godotPath --headless --path godot --script res://compare_native_footprint_origin.gd
        if ($LASTEXITCODE -ne 0) { throw 'Footprint origin differs from original' }
        python tools\native_solar_reference.py --unit armmex
        if ($LASTEXITCODE -ne 0) { throw 'Original extractor lifecycle failed' }
        & $godotPath --headless --path godot --script res://compare_native_solar.gd -- --armmex
        if ($LASTEXITCODE -ne 0) { throw 'Extractor lifecycle differs from original' }
        python tools\prepare_map_metal.py
        if ($LASTEXITCODE -ne 0) { throw 'Comet metal preparation failed' }
        python tools\native_comet_metal.py
        if ($LASTEXITCODE -ne 0) { throw 'Comet metal grid differs from original feature pass' }
        python tools\native_feature_metal.py
        if ($LASTEXITCODE -ne 0) { throw 'Feature metal overlay differs from original' }
        python tools\native_feature_blocking.py
        if ($LASTEXITCODE -ne 0) { throw 'Feature blocking differs from original terrain predicate' }
        python tools\native_extractor_yield.py
        if ($LASTEXITCODE -ne 0) { throw 'Native extractor yield failed' }
        & $godotPath --headless --path godot --script res://compare_native_extractor_yield.gd
        if ($LASTEXITCODE -ne 0) { throw 'Extractor yield differs from original' }
        python tools\native_maker_economy.py
        if ($LASTEXITCODE -ne 0) { throw 'Native maker economy failed' }
        & $godotPath --headless --path godot --script res://compare_native_maker_economy.gd
        if ($LASTEXITCODE -ne 0) { throw 'Maker economy differs from original' }
        & $godotPath --headless --path godot --script res://compare_native_live_makers.gd
        if ($LASTEXITCODE -ne 0) { throw 'Live maker economy differs from original' }
        python tools\native_resource_schedule.py
        if ($LASTEXITCODE -ne 0) { throw 'Native resource schedule failed' }
        & $godotPath --headless --path godot --script res://compare_native_resource_schedule.gd
        if ($LASTEXITCODE -ne 0) { throw 'Resource schedule differs from original' }
        python tools\native_resource_debt.py
        if ($LASTEXITCODE -ne 0) { throw 'Native resource debt settlement failed' }
        & $godotPath --headless --path godot --script res://compare_native_resource_debt.gd
        if ($LASTEXITCODE -ne 0) { throw 'Resource debt settlement differs from original' }
        python tools\native_resource_allocation.py
        if ($LASTEXITCODE -ne 0) { throw 'Native resource allocation failed' }
        & $godotPath --headless --path godot --script res://compare_native_resource_allocation.gd
        if ($LASTEXITCODE -ne 0) { throw 'Resource allocation differs from original' }
        python tools\native_upkeep_gate.py
        if ($LASTEXITCODE -ne 0) { throw 'Native upkeep gate failed' }
        & $godotPath --headless --path godot --script res://compare_native_upkeep_gate.gd
        if ($LASTEXITCODE -ne 0) { throw 'Upkeep gate differs from original' }
        python tools\native_solar_reference.py --unit armmakr
        if ($LASTEXITCODE -ne 0) { throw 'Original metal maker lifecycle failed' }
        & $godotPath --headless --path godot --script res://compare_native_solar.gd -- --armmakr
        if ($LASTEXITCODE -ne 0) { throw 'Metal maker lifecycle differs from original' }
        python tools\native_direct_deadline.py
        if ($LASTEXITCODE -ne 0) { throw 'Original direct deadline failed' }
        & $godotPath --headless --path godot --script res://compare_native_direct_deadline.gd
        if ($LASTEXITCODE -ne 0) { throw 'Direct deadline differs from original executable' }
        foreach ($missileUnit in @('armsam', 'armjeth')) {
            python tools\native_firing_reference.py --unit $missileUnit
            if ($LASTEXITCODE -ne 0) { throw "Original $missileUnit firing reference failed" }
            & $godotPath --headless --path godot --script res://compare_native_firing.gd -- "--$missileUnit"
            if ($LASTEXITCODE -ne 0) { throw "$missileUnit firing differs from original executable" }
        }
        python tools\native_guided_motion.py
        if ($LASTEXITCODE -ne 0) { throw 'Original guided motion failed' }
        & $godotPath --headless --path godot --script res://compare_native_guided_motion.gd
        if ($LASTEXITCODE -ne 0) { throw 'Guided motion differs from original executable' }
        python tools\native_missile_target.py
        if ($LASTEXITCODE -ne 0) { throw 'Original missile target selection failed' }
        & $godotPath --headless --path godot --script res://compare_native_missile_target.gd
        if ($LASTEXITCODE -ne 0) { throw 'Missile target selection differs from original executable' }
        python tools\native_missile_steering.py
        if ($LASTEXITCODE -ne 0) { throw 'Original missile steering failed' }
        & $godotPath --headless --path godot --script res://compare_native_missile_steering.gd
        if ($LASTEXITCODE -ne 0) { throw 'Missile steering differs from original executable' }
        python tools\native_firing_reference.py --unit armwar
        if ($LASTEXITCODE -ne 0) { throw 'Original Warrior firing reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_firing.gd -- --armwar
        if ($LASTEXITCODE -ne 0) { throw 'Warrior firing differs from original executable' }
        python tools\native_firing_reference.py --unit armrock
        if ($LASTEXITCODE -ne 0) { throw 'Original Rocko firing reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_firing.gd -- --armrock
        if ($LASTEXITCODE -ne 0) { throw 'Rocko firing differs from original executable' }
        python tools\native_rocket_motion.py
        if ($LASTEXITCODE -ne 0) { throw 'Original rocket motion failed' }
        & $godotPath --headless --path godot --script res://compare_native_rocket_motion.gd
        if ($LASTEXITCODE -ne 0) { throw 'Rocket motion differs from original executable' }
        python tools\native_firing_reference.py --unit armpw
        if ($LASTEXITCODE -ne 0) { throw 'Original Peewee firing reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_firing.gd -- --armpw
        if ($LASTEXITCODE -ne 0) { throw 'Peewee firing differs from original executable' }
        python tools\native_emg_launch.py
        if ($LASTEXITCODE -ne 0) { throw 'Original direct launch failed' }
        & $godotPath --headless --path godot --script res://compare_native_direct_launch.gd
        if ($LASTEXITCODE -ne 0) { throw 'Direct launch differs from original executable' }
        python tools\native_emg_lifetime.py
        if ($LASTEXITCODE -ne 0) { throw 'Original EMG lifetime checks failed' }
        python tools\native_burst_cleanup.py
        if ($LASTEXITCODE -ne 0) { throw 'Original burst cleanup checks failed' }
        python tools\native_burst_update.py
        if ($LASTEXITCODE -ne 0) { throw 'Original burst update failed' }
        & $godotPath --headless --path godot --script res://compare_native_burst.gd
        if ($LASTEXITCODE -ne 0) { throw 'Burst transition differs from original executable' }
        python tools\native_weapon_reload.py
        if ($LASTEXITCODE -ne 0) { throw 'Original weapon reload reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_weapon_reload.gd
        if ($LASTEXITCODE -ne 0) { throw 'Weapon reload differs from original executable' }
        python tools\native_firing_reference.py --unit armham
        if ($LASTEXITCODE -ne 0) { throw 'Original Hammer firing reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_firing.gd -- --armham
        if ($LASTEXITCODE -ne 0) { throw 'Hammer firing differs from original executable' }
        python tools\native_firing_reference.py --unit armstump
        if ($LASTEXITCODE -ne 0) { throw 'Original Stumpy firing reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_firing.gd -- --armstump
        if ($LASTEXITCODE -ne 0) { throw 'Stumpy firing differs from original interpreter' }
        python tools\native_ballistic_deadline.py
        if ($LASTEXITCODE -ne 0) { throw 'Original ballistic deadline reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_ballistic_deadline.gd
        if ($LASTEXITCODE -ne 0) { throw 'Ballistic deadline differs from original executable' }
        python tools\native_ballistic_lifetime.py
        if ($LASTEXITCODE -ne 0) { throw 'Original ballistic lifetime reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_ballistic_lifetime.gd
        if ($LASTEXITCODE -ne 0) { throw 'Ballistic lifetime differs from original executable' }
        python tools\native_collision_rect.py
        if ($LASTEXITCODE -ne 0) { throw 'Original collision rectangle reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_collision_rect.gd
        if ($LASTEXITCODE -ne 0) { throw 'Collision rectangle differs from original executable' }
        python tools\native_collision_grid.py
        if ($LASTEXITCODE -ne 0) { throw 'Original collision grid reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_collision_grid.gd
        if ($LASTEXITCODE -ne 0) { throw 'Collision grid differs from original executable' }
        python tools\native_projectile_collision.py
        if ($LASTEXITCODE -ne 0) { throw 'Original projectile collision reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_projectile_collision.gd
        if ($LASTEXITCODE -ne 0) { throw 'Projectile collision differs from original executable' }
        python tools\native_target_vertices.py
        if ($LASTEXITCODE -ne 0) { throw 'Original target vertices reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_target_vertices.gd
        if ($LASTEXITCODE -ne 0) { throw 'Target vertices differ from original executable' }
        python tools\native_target_point.py
        if ($LASTEXITCODE -ne 0) { throw 'Original target point reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_target_point.gd
        if ($LASTEXITCODE -ne 0) { throw 'Target point differs from original executable' }
        python tools\native_unit_bounds.py
        if ($LASTEXITCODE -ne 0) { throw 'Original unit bounds reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_unit_bounds.gd
        if ($LASTEXITCODE -ne 0) { throw 'Unit bounds differ from original executable' }
        python tools\native_damage_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original damage reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_damage.gd
        if ($LASTEXITCODE -ne 0) { throw 'Weapon damage differs from original executable' }
        python tools\native_splash_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original splash reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_splash.gd
        if ($LASTEXITCODE -ne 0) { throw 'Splash falloff differs from original executable' }
        python tools\native_piece_origin.py
        if ($LASTEXITCODE -ne 0) { throw 'Original piece origin reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_piece_origin.gd
        if ($LASTEXITCODE -ne 0) { throw 'Piece origins differ from original executable' }
        python tools\native_map_gravity.py
        if ($LASTEXITCODE -ne 0) { throw 'Map gravity differs from original executable' }
        python tools\native_wind_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original wind update reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_wind.gd
        if ($LASTEXITCODE -ne 0) { throw 'Wind state differs from original executable' }
        python tools\native_ballistic_launch.py
        if ($LASTEXITCODE -ne 0) { throw 'Original ballistic launch reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_ballistic_launch.gd
        if ($LASTEXITCODE -ne 0) { throw 'Ballistic launch differs from original executable' }
        python tools\native_ballistic_aim.py
        if ($LASTEXITCODE -ne 0) { throw 'Original ballistic aim reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_ballistic_aim.gd
        if ($LASTEXITCODE -ne 0) { throw 'Ballistic aim differs from original executable' }
        python tools\native_ballistic_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original ballistic integration reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_ballistics.gd
        if ($LASTEXITCODE -ne 0) { throw 'Ballistic integration differs from original executable' }
        python tools\native_firing_reference.py --unit corraid
        if ($LASTEXITCODE -ne 0) { throw 'Original Raider firing reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_firing.gd -- --corraid
        if ($LASTEXITCODE -ne 0) { throw 'Raider firing script differs from original interpreter' }
        # Core roster firing traces must exist before the tank origin/target oracles below.
        python tools\native_killed_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original Killed script reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_killed.gd
        if ($LASTEXITCODE -ne 0) { throw 'Killed scripts differ from original interpreter' }
        python tools\prepare_visibility.py
        if ($LASTEXITCODE -ne 0) { throw 'Visibility asset preparation failed' }
        python tools\native_los_tables.py
        if ($LASTEXITCODE -ne 0) { throw 'Native LOS tables failed' }
        & $godotPath --headless --path godot --script res://compare_native_los_tables.gd
        if ($LASTEXITCODE -ne 0) { throw 'LOS tables native comparison failed' }
        python tools\native_los_heights.py
        if ($LASTEXITCODE -ne 0) { throw 'Native LOS heights failed' }
        & $godotPath --headless --path godot --script res://compare_native_los_heights.gd
        if ($LASTEXITCODE -ne 0) { throw 'LOS heights native comparison failed' }
        python tools\native_hit_notify.py
        if ($LASTEXITCODE -ne 0) { throw 'Native hit notification failed' }
        & $godotPath --headless --path godot --script res://compare_native_hit_notify.gd
        if ($LASTEXITCODE -ne 0) { throw 'Hit notification native comparison failed' }
        python tools\native_map_features.py
        if ($LASTEXITCODE -ne 0) { throw 'Native map feature loading failed' }
        python tools\compare_native_map_features.py
        if ($LASTEXITCODE -ne 0) { throw 'Map feature loader native comparison failed' }
        python tools\native_feature_damage.py
        if ($LASTEXITCODE -ne 0) { throw 'Native feature damage failed' }
        & $godotPath --headless --path godot --script res://compare_native_feature_damage.gd
        if ($LASTEXITCODE -ne 0) { throw 'Feature damage native comparison failed' }
        python tools\native_beam_motion.py
        if ($LASTEXITCODE -ne 0) { throw 'Original beam motion reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_beam_motion.gd
        if ($LASTEXITCODE -ne 0) { throw 'Beam motion differs from original executable' }
        foreach ($coreUnit in @('corthud', 'corlevlr', 'corstorm', 'cormist', 'corcrash', 'armfav', 'corfav', 'corgator', 'corak', 'armcom', 'corcom')) {
            python tools\native_firing_reference.py --unit $coreUnit
            if ($LASTEXITCODE -ne 0) { throw "Original $coreUnit firing reference failed" }
            & $godotPath --headless --path godot --script res://compare_native_firing.gd -- "--$coreUnit"
            if ($LASTEXITCODE -ne 0) { throw "$coreUnit firing differs from original interpreter" }
        }
        python tools\native_firing_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original Flash firing reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_firing.gd
        if ($LASTEXITCODE -ne 0) { throw 'Flash firing script differs from original interpreter' }
        python tools\native_tank_targets.py
        if ($LASTEXITCODE -ne 0) { throw 'Original tank target reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_tank_targets.gd
        if ($LASTEXITCODE -ne 0) { throw 'Tank targets differ from original executable' }
        python tools\native_tank_targets.py --roster
        if ($LASTEXITCODE -ne 0) { throw 'Original roster target reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_tank_targets.gd -- --roster
        if ($LASTEXITCODE -ne 0) { throw 'Roster targets differ from original executable' }
        python tools\native_tank_origins.py
        if ($LASTEXITCODE -ne 0) { throw 'Original tank origin reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_tank_origins.gd
        if ($LASTEXITCODE -ne 0) { throw 'Tank origins differ from original setters and transforms' }
        python tools\native_cannon_launch.py
        if ($LASTEXITCODE -ne 0) { throw 'Original cannon shot composition reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_cannon_launch.gd
        if ($LASTEXITCODE -ne 0) { throw 'Cannon shot composition differs from original executable' }
        python tools\native_weapon_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original weapon scalar reference failed' }
        python tools\compare_native_weapons.py
        if ($LASTEXITCODE -ne 0) { throw 'Weapon scalars differ from original executable' }
        python tools\native_mobile_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original mobile script reference run failed' }
        & $godotPath --headless --path godot --script res://compare_native_units.gd
        if ($LASTEXITCODE -ne 0) { throw 'Mobile scripts differ from original interpreter' }
        python tools\native_factory_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original factory reference run failed' }
        & $godotPath --headless --path godot --script res://compare_native_factory.gd
        if ($LASTEXITCODE -ne 0) { throw 'Factory scripts differ from original interpreter' }
        python tools\native_structure_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original Core structure reference run failed' }
        & $godotPath --headless --path godot --script res://compare_native_structures.gd
        if ($LASTEXITCODE -ne 0) { throw 'Core structure scripts differ from original interpreter' }
        python tools\native_solar_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original solar reference run failed' }
        & $godotPath --headless --path godot --script res://compare_native_solar.gd
        if ($LASTEXITCODE -ne 0) { throw 'Solar script differs from original interpreter' }
        foreach ($coreResource in @('corsolar', 'cormakr', 'cormex', 'corwin', 'cortide')) {
            python tools\native_solar_reference.py --unit $coreResource
            if ($LASTEXITCODE -ne 0) { throw "Original $coreResource reference failed" }
            & $godotPath --headless --path godot --script res://compare_native_solar.gd -- "--$coreResource"
            if ($LASTEXITCODE -ne 0) { throw "$coreResource script differs from original interpreter" }
        }
        python tools\native_cob_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original interpreter reference run failed' }
        & $godotPath --headless --path godot --script res://compare_native_cob.gd
        if ($LASTEXITCODE -ne 0) { throw 'Runtime differs from original interpreter' }
        python tools\native_cob_reference.py --cob local/unit-assets/corcom/script.cob --output local/scripts/native-trace-corcom.json
        if ($LASTEXITCODE -ne 0) { throw 'Original Core commander interpreter reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_cob.gd -- --core
        if ($LASTEXITCODE -ne 0) { throw 'Core commander runtime differs from original interpreter' }
        python tools\native_movement_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original movement reference run failed' }
        & $godotPath --headless --path godot --script res://compare_native_movement.gd
        if ($LASTEXITCODE -ne 0) { throw 'Movement primitives differ from original executable' }
        python tools\native_construction_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original construction reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_construction.gd
        if ($LASTEXITCODE -ne 0) { throw 'Construction primitive differs from original executable' }
    }
} finally { Pop-Location }
