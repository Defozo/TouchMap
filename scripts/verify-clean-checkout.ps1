param([string]$Revision = 'HEAD', [string]$Distribution = 'Ubuntu')
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$mappedPath = & wsl.exe -d $Distribution -- wslpath -a ($repository.Replace('\', '/'))
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve the project path inside WSL.' }
& wsl.exe -d $Distribution -- bash "$($mappedPath.Trim())/scripts/verify-clean-checkout.sh" $Revision
if ($LASTEXITCODE -ne 0) { throw "Clean checkout verification failed (exit $LASTEXITCODE)." }
