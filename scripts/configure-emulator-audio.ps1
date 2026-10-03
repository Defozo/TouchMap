param(
    [Parameter(Mandatory)][string]$Target,
    [ValidateSet('inspect', 'apply', 'restore')][string]$Action = 'inspect',
    [string]$Distribution = 'Ubuntu'
)
$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path "$PSScriptRoot/..").Path
$mappedPath = & wsl.exe -d $Distribution -- wslpath -a ($repository.Replace('\', '/'))
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve the project path inside WSL.' }
& wsl.exe -d $Distribution -- python3 "$($mappedPath.Trim())/scripts/configure-emulator-audio.py" --device $Target $Action
if ($LASTEXITCODE -ne 0) { throw "Emulator audio $Action failed (exit $LASTEXITCODE)." }
