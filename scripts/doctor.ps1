param([string]$Distribution = 'Ubuntu')
. "$PSScriptRoot/Platform.Common.ps1"
Invoke-TouchMapPlatform -Action doctor -Distribution $Distribution
