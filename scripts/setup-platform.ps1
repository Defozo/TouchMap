param([string]$Distribution = 'Ubuntu')
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$mappedPath = & wsl.exe -d $Distribution -- wslpath -a ($repository.Replace('\', '/'))
if ($LASTEXITCODE -ne 0) { throw 'Install WSL2 Ubuntu first.' }
$linuxRepository = $mappedPath.Trim()
& wsl.exe -d $Distribution -- bash "$linuxRepository/scripts/setup-platform.sh"
if ($LASTEXITCODE -ne 0) { throw 'Toolchain setup failed.' }
