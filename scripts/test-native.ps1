param([Parameter(Mandatory)][string]$Target, [string]$Distribution = 'Ubuntu')
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$mappedPath = & wsl.exe -d $Distribution -- wslpath -a ($repository.Replace('\', '/'))
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve the project path inside WSL.' }
& wsl.exe -d $Distribution -- bash "$($mappedPath.Trim())/scripts/test-native.sh" $Target
if ($LASTEXITCODE -ne 0) { throw "Native tests failed (exit $LASTEXITCODE)." }
