param([switch]$Prepare)
$ErrorActionPreference = 'Stop'
$workspacePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ($Prepare -or -not (Test-Path -LiteralPath (Join-Path $workspacePath 'local\viewer-assets\armcom.cob.json'))) {
    Push-Location $workspacePath
    try {
        python (Join-Path $PSScriptRoot 'prepare_viewer.py')
        if ($LASTEXITCODE -ne 0) { throw 'Asset preparation failed' }
    } finally { Pop-Location }
}
$godotCommand = Get-Command godot -ErrorAction SilentlyContinue
$godotPath = if ($godotCommand) { $godotCommand.Source } else {
    (Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\Godot*_win64.exe" | Select-Object -First 1).FullName
}
if (-not $godotPath) { throw 'Godot 4 is required. Add godot to PATH.' }
& $godotPath --path (Join-Path $workspacePath 'godot')
