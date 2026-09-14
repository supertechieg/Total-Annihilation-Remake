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
    $unitBundleCurrent = $unitMetadata.weapon_runtime_version -eq 5 -and $unitMetadata.movement_runtime_version -eq 1 -and $unitMetadata.feature_runtime_version -eq 5
}
if ($Prepare -or -not $unitBundleCurrent) {
    Push-Location $workspacePath
    try {
        python (Join-Path $PSScriptRoot 'prepare_units.py')
        if ($LASTEXITCODE -ne 0) { throw 'Unit bundle preparation failed' }
    } finally { Pop-Location }
}
$mapMetadataPath = Join-Path $workspacePath 'local\viewer-assets\metal.json'
$mapBundleCurrent = $false
if ((Test-Path -LiteralPath $mapMetadataPath) -and (Test-Path -LiteralPath (Join-Path $workspacePath 'local\viewer-assets\features.bin'))) {
    $mapMetadata = Get-Content -LiteralPath $mapMetadataPath -Raw | ConvertFrom-Json
    $mapBundleCurrent = $mapMetadata.feature_blocking_version -eq 1
}
$mapsIndexPath = Join-Path $workspacePath 'local\maps\index.json'
$mapsBundleCurrent = $false
if (Test-Path -LiteralPath $mapsIndexPath) {
    $mapsMetadata = Get-Content -LiteralPath $mapsIndexPath -Raw | ConvertFrom-Json
    $mapsBundleCurrent = $mapsMetadata.version -eq 2
}
foreach ($bundle in @(
    # Older map bundles predate the static feature-blocking grid.
    @{ Index = 'local\viewer-assets\metal.bin'; Script = 'prepare_map_metal.py'; Current = $mapBundleCurrent },
    # Skirmish maps (index version 2: original loader overlap and void resolution).
    @{ Index = 'local\maps\index.json'; Script = 'prepare_maps.py'; Current = $mapsBundleCurrent },
    @{ Index = 'local\weapon-sounds\index.json'; Script = 'prepare_weapon_sounds.py'; Current = $true },
    @{ Index = 'local\weapon-effects\index.json'; Script = 'prepare_weapon_effects.py'; Current = $true }
)) {
    if ($Prepare -or -not $unitBundleCurrent -or -not $bundle.Current -or -not (Test-Path -LiteralPath (Join-Path $workspacePath $bundle.Index))) {
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
