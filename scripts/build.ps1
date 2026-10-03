param(
    [ValidateSet('openharmonyApi20')][string]$Product = 'openharmonyApi20',
    [ValidateSet('debug','release')][string]$BuildMode = 'debug',
    [string]$Distribution = 'Ubuntu'
)
. "$PSScriptRoot/Platform.Common.ps1"
Invoke-TouchMapPlatform -Action build -Arguments @($Product, $BuildMode) -Distribution $Distribution
