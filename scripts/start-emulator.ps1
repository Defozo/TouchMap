param([string]$Distribution = 'Ubuntu')
. "$PSScriptRoot/Platform.Common.ps1"
New-Item -ItemType Directory -Force -Path "$PSScriptRoot/../docs/evidence" | Out-Null
Invoke-TouchMapPlatform -Action emulator -Distribution $Distribution
