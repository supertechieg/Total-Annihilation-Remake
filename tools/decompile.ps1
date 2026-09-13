param(
    [string]$GamePath = 'C:\Program Files (x86)\GOG Galaxy\Games\Total Annihilation',
    [string]$GhidraPath = (Join-Path $PSScriptRoot '..\local\tools\ghidra_12.1.3_PUBLIC')
)
$ErrorActionPreference = 'Stop'
$workspacePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$localPath = Join-Path $workspacePath 'local'
$originalPath = Join-Path $localPath 'original\TotalA.exe'
$projectPath = Join-Path $localPath 'ghidra-projects'
$outputPath = Join-Path $localPath 'decompiled'
$headlessPath = Join-Path $GhidraPath 'support\analyzeHeadless.bat'
if (-not (Test-Path -LiteralPath $headlessPath)) { throw "Ghidra missing: $headlessPath" }
New-Item -ItemType Directory -Force -Path (Split-Path $originalPath),$projectPath,$outputPath | Out-Null
$sourcePath = Join-Path $GamePath 'TotalA.exe'
if (Test-Path -LiteralPath $originalPath) {
    if ((Get-FileHash -LiteralPath $sourcePath).Hash -ne (Get-FileHash -LiteralPath $originalPath).Hash) {
        throw 'Installation differs from existing analysis copy; use a separate project for this version.'
    }
} else {
    Copy-Item -LiteralPath $sourcePath -Destination $originalPath
}
if (Test-Path -LiteralPath (Join-Path $projectPath 'TotalAnnihilation.gpr')) {
    throw 'Analysis project already exists. Open it in Ghidra; this script does not overwrite existing analysis.'
}
& $headlessPath $projectPath TotalAnnihilation -import $originalPath -scriptPath $PSScriptRoot -postScript ExportAnalysis.java $outputPath -postScript ExportStringReferences.java $outputPath -log (Join-Path $localPath 'ghidra-analysis.log')
if ($LASTEXITCODE -ne 0) { throw "Ghidra failed with exit code $LASTEXITCODE" }
if (-not (Test-Path -LiteralPath (Join-Path $outputPath 'export-status.txt'))) { throw 'Export did not complete; inspect the Ghidra log.' }
Get-Content -LiteralPath (Join-Path $outputPath 'export-status.txt')
