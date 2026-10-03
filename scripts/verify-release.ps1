param([switch]$RequireAllGates)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
Push-Location $project
try {
    $arguments = @('run', '--project', 'backend', 'python', 'scripts/verify-release.py')
    if ($RequireAllGates) { $arguments += '--require-all-gates' }
    & uv @arguments
    if ($LASTEXITCODE) { throw 'Release verification failed. Read the emitted report.' }
} finally { Pop-Location }
