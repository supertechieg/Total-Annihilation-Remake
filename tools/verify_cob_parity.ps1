# COB VM parity (CP0): regenerates the original-interpreter traces touched by RAND/EMIT_SFX/overflow/health work
# and compares the Godot VM against them. Native-only; the NORMAL suite covers godot/test_cob_rand.gd.
param([switch]$FiringOnly)
$ErrorActionPreference = 'Stop'
$workspacePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$godotCommand = Get-Command godot -ErrorAction SilentlyContinue
$godotPath = if ($godotCommand) { $godotCommand.Source } else {
    (Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\Godot*_win64_console.exe" | Select-Object -First 1).FullName
}
if (-not $godotPath) { throw 'Godot 4 is required. Add godot to PATH.' }
$failures = @()
function Step([string]$Label, [scriptblock]$Body) {
    & $Body
    if ($LASTEXITCODE -ne 0) { $script:failures += $Label; Write-Host "FAILED: $Label" }
}
Push-Location $workspacePath
try {
    if (-not $FiringOnly) {
    Step 'COB RAND/SFX/overflow unit test' { & $godotPath --headless --path godot --script res://test_cob_rand.gd }
    Step 'COB live-world health feed test' { & $godotPath --headless --path godot --script res://test_cob_health_feed.gd }
    Step 'Native health read reference' { python tools\native_health_read.py }
    Step 'Native health read comparison' { & $godotPath --headless --path godot --script res://compare_native_health_read.gd }
    Step 'Native overflow reference' { python tools\native_cob_overflow.py }
    Step 'Native overflow comparison' { & $godotPath --headless --path godot --script res://compare_native_cob_overflow.gd }
    Step 'Native Commander reference' { python tools\native_cob_reference.py }
    Step 'Native Commander comparison' { & $godotPath --headless --path godot --script res://compare_native_cob.gd }
    Step 'Native mobile reference' { python tools\native_mobile_reference.py }
    Step 'Native mobile comparison' { & $godotPath --headless --path godot --script res://compare_native_units.gd }
    Step 'Native damaged mobile reference' { python tools\native_mobile_reference.py --damaged }
    Step 'Native damaged mobile comparison' { & $godotPath --headless --path godot --script res://compare_native_units.gd -- --damaged }
    Step 'Native factory reference' { python tools\native_factory_reference.py }
    Step 'Native factory comparison' { & $godotPath --headless --path godot --script res://compare_native_factory.gd }
    Step 'Native damaged factory reference' { python tools\native_factory_reference.py --damaged }
    Step 'Native damaged factory comparison' { & $godotPath --headless --path godot --script res://compare_native_factory.gd -- --damaged }
    }
    foreach ($unit in @('armflash', 'corraid', 'armstump', 'armham', 'armpw', 'armrock', 'armwar', 'armsam', 'armjeth',
                        'corthud', 'corlevlr', 'corstorm', 'cormist', 'corcrash', 'armfav', 'corfav', 'corgator', 'corak',
                        'armcom', 'corcom', 'corpyro')) {
        foreach ($damaged in @($false, $true)) {
            [string[]]$extra = if ($damaged) { @("--damaged") } else { @() }
            Step "Native $unit firing reference $extra" { python tools\native_firing_reference.py --unit $unit @extra }
            Step "Native $unit firing comparison $extra" { & $godotPath --headless --path godot --script res://compare_native_firing.gd -- "--$unit" @extra }
        }
    }
} finally {
    Pop-Location
}
if ($failures.Count) { Write-Host "COB_PARITY_FAILURES $($failures.Count): $($failures -join '; ')"; exit 1 }
Write-Host 'COB_PARITY all steps passed'
exit 0
