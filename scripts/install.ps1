param([Parameter(Mandatory)][string]$Target, [string]$Distribution = 'Ubuntu')
. "$PSScriptRoot/Platform.Common.ps1"
Invoke-TouchMapPlatform -Action install -Arguments @($Target) -Distribution $Distribution
