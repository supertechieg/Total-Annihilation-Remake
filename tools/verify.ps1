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
    & $godotPath --headless --path godot --script res://test_cannon_combat.gd
    if ($LASTEXITCODE -ne 0) { throw 'Cannon combat checks failed' }
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
    & $godotPath --headless --path godot --quit-after 2 -- --builder-demo
    if ($LASTEXITCODE -ne 0) { throw 'Real-map mobile builder construction failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-combat
    if ($LASTEXITCODE -ne 0) { throw 'Real-map Flash combat failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-duel
    if ($LASTEXITCODE -ne 0) { throw 'Real-map armed tank duel failed' }
    & $godotPath --headless --path godot --quit-after 2 -- --verify-stumpy
    if ($LASTEXITCODE -ne 0) { throw 'Real-map Stumpy duel failed' }
    if ($Native) {
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
        python tools\native_firing_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original Flash firing reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_firing.gd
        if ($LASTEXITCODE -ne 0) { throw 'Flash firing script differs from original interpreter' }
        python tools\native_tank_origins.py
        if ($LASTEXITCODE -ne 0) { throw 'Original tank origin reference failed' }
        & $godotPath --headless --path godot --script res://compare_native_tank_origins.gd
        if ($LASTEXITCODE -ne 0) { throw 'Tank origins differ from original setters and transforms' }
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
        python tools\native_solar_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original solar reference run failed' }
        & $godotPath --headless --path godot --script res://compare_native_solar.gd
        if ($LASTEXITCODE -ne 0) { throw 'Solar script differs from original interpreter' }
        python tools\native_cob_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original interpreter reference run failed' }
        & $godotPath --headless --path godot --script res://compare_native_cob.gd
        if ($LASTEXITCODE -ne 0) { throw 'Runtime differs from original interpreter' }
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
