param([switch]$Cloud, [switch]$Wsl, [switch]$Injected, [int]$Port = 8080, [string]$Distribution = 'Ubuntu')
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
if ($Cloud -and -not $Injected) {
    $scriptArguments = @('-NoProfile', '-File', $PSCommandPath, '-Cloud', '-Injected', '-Port', "$Port", '-Distribution', $Distribution)
    if ($Wsl) { $scriptArguments += '-Wsl' }
    & psst GOOGLE_AI_STUDIO_API_KEY ELEVENLABS_API_KEY -- pwsh @scriptArguments
    exit $LASTEXITCODE
}
$env:TOUCHMAP_CLOUD_AI_ENABLED = if ($Cloud) { 'true' } else { 'false' }
$env:TOUCHMAP_CLOUD_TTS_ENABLED = if ($Cloud) { 'true' } else { 'false' }
$env:ELEVENLABS_VOICE_ID = 'hpp4J3VqNfWAUOO0d1Us'
if ($Wsl) {
    # WSLENV transports inherited values; no credentials enter arguments or files.
    $names = @('GOOGLE_AI_STUDIO_API_KEY/u', 'ELEVENLABS_API_KEY/u', 'TOUCHMAP_CLOUD_AI_ENABLED/u', 'TOUCHMAP_CLOUD_TTS_ENABLED/u', 'ELEVENLABS_VOICE_ID/u')
    $env:WSLENV = ((@($env:WSLENV) + $names) | Where-Object { $_ }) -join ':'
    $linuxDirectory = (& wsl.exe -d $Distribution -- wslpath -a $projectDirectory.Replace('\', '/')).Trim()
    & wsl.exe -d $Distribution -- bash "$linuxDirectory/scripts/backend-wsl.sh" $linuxDirectory "$Port"
    exit $LASTEXITCODE
}
Push-Location (Join-Path $projectDirectory 'backend')
try {
    & uv sync --frozen
    if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
    & uv run touchmap serve --host 127.0.0.1 --port $Port
    exit $LASTEXITCODE
} finally { Pop-Location }
