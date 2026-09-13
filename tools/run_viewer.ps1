param([switch]$Prepare, [switch]$PrepareOnly)
$ErrorActionPreference = 'Stop'
$workspacePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$scenePath = Join-Path $workspacePath 'local\viewer-assets\scene.json'
$viewerBundleCurrent = $false
if (Test-Path -LiteralPath $scenePath) {
    $sceneMetadata = Get-Content -LiteralPath $scenePath -Raw | ConvertFrom-Json
    $viewerBundleCurrent = $sceneMetadata.environment_version -eq 1 -and $null -ne $sceneMetadata.environment.tidal_strength
}
if ($Prepare -or -not $viewerBundleCurrent -or -not (Test-Path -LiteralPath (Join-Path $workspacePath 'local\viewer-assets\armcom.cob.json'))) {
    Push-Location $workspacePath
    try {
        python (Join-Path $PSScriptRoot 'prepare_viewer.py')
        if ($LASTEXITCODE -ne 0) { throw 'Asset preparation failed' }
    } finally { Pop-Location }
}
$unitIndexPath = Join-Path $workspacePath 'local\unit-assets\index.json'
$unitBundleCurrent = $false
if (Test-Path -LiteralPath $unitIndexPath) {
    $unitMetadata = Get-Content -LiteralPath $unitIndexPath -Raw | ConvertFrom-Json
    $unitBundleCurrent = $unitMetadata.weapon_runtime_version -eq 4 -and $unitMetadata.movement_runtime_version -eq 1
}
if ($Prepare -or -not $unitBundleCurrent) {
    Push-Location $workspacePath
    try {
        python (Join-Path $PSScriptRoot 'prepare_units.py')
        if ($LASTEXITCODE -ne 0) { throw 'Unit bundle preparation failed' }
    } finally { Pop-Location }
}
foreach ($bundle in @(
    @{ Index = 'local\viewer-assets\metal.bin'; Script = 'prepare_map_metal.py' },
    @{ Index = 'local\weapon-sounds\index.json'; Script = 'prepare_weapon_sounds.py' },
    @{ Index = 'local\weapon-effects\index.json'; Script = 'prepare_weapon_effects.py' }
)) {
    if ($Prepare -or -not $unitBundleCurrent -or -not (Test-Path -LiteralPath (Join-Path $workspacePath $bundle.Index))) {
        Push-Location $workspacePath
        try {
            python (Join-Path $PSScriptRoot $bundle.Script)
            if ($LASTEXITCODE -ne 0) { throw "Preparation failed: $($bundle.Script)" }
        } finally { Pop-Location }
    }
}
if ($PrepareOnly) {
    Write-Output 'All viewer bundles are prepared.'
    return
}
$godotCommand = Get-Command godot -ErrorAction SilentlyContinue
$godotPath = if ($godotCommand) { $godotCommand.Source } else {
    (Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\Godot*_win64.exe" | Select-Object -First 1).FullName
}
if (-not $godotPath) { throw 'Godot 4 is required. Add godot to PATH.' }
& $godotPath --path (Join-Path $workspacePath 'godot')
