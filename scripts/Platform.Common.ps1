Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Invoke-TouchMapPlatform {
    param([Parameter(Mandatory)][string]$Action, [string[]]$Arguments = @(), [string]$Distribution = 'Ubuntu')
    $repository = Split-Path -Parent $PSScriptRoot
    $mappedPath = & wsl.exe -d $Distribution -- wslpath -a ($repository.Replace('\', '/'))
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve the project path inside WSL.' }
    $linuxRepository = $mappedPath.Trim()
    & wsl.exe -d $Distribution -- bash "$linuxRepository/scripts/platform.sh" $Action $linuxRepository @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Platform command '$Action' failed (exit $LASTEXITCODE)." }
}
