param(
    [Parameter(Mandatory = $true)][string]$Target,
    [ValidateRange(1,1000)][int]$Count = 100,
    [string]$Distribution = 'Ubuntu'
)
$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path "$PSScriptRoot/..").Path
$mappedPath = & wsl.exe -d $Distribution -- wslpath -a ($repository.Replace('\', '/'))
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve repository in WSL.' }
& wsl.exe -d $Distribution -- bash "$($mappedPath.Trim())/scripts/test-audio.sh" $Target $Count
if ($LASTEXITCODE -ne 0) { throw "Native audio benchmark failed with exit code $LASTEXITCODE." }
