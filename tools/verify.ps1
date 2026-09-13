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
    & $godotPath --headless --path godot -- --verify
    if ($LASTEXITCODE -ne 0) { throw 'Viewer checks failed' }
    if ($Native) {
        python tools\native_cob_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original interpreter reference run failed' }
        & $godotPath --headless --path godot --script res://compare_native_cob.gd
        if ($LASTEXITCODE -ne 0) { throw 'Runtime differs from original interpreter' }
        python tools\native_movement_reference.py
        if ($LASTEXITCODE -ne 0) { throw 'Original movement reference run failed' }
        & $godotPath --headless --path godot --script res://compare_native_movement.gd
        if ($LASTEXITCODE -ne 0) { throw 'Movement primitives differ from original executable' }
    }
} finally { Pop-Location }
