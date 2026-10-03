param([switch]$SkipBackend)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
Push-Location $project
try {
    npm ci
    if ($LASTEXITCODE) { throw 'Dependency installation failed.' }
    npm test
    if ($LASTEXITCODE) { throw 'Domain tests failed.' }
    npm run typecheck
    if ($LASTEXITCODE) { throw 'Type checking failed.' }
    if (-not $SkipBackend) {
        uv sync --project backend --frozen
        if ($LASTEXITCODE) { throw 'Python dependency installation failed.' }
        uv run --project backend pytest backend/tests
        if ($LASTEXITCODE) { throw 'Backend tests failed.' }
    }
} finally { Pop-Location }
