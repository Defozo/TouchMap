param(
  [string]$Revision = 'v1',
  [string]$RuntimePython = 'python'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$deckPath = Join-Path $projectRoot "dist/touchmap-presentation-$Revision.pptx"
$pdfPath = Join-Path $projectRoot "dist/touchmap-presentation-$Revision.pdf"
$renderPath = Join-Path $projectRoot ".local/presentation/$Revision/rendered"
if (!(Test-Path -LiteralPath $deckPath)) { throw "Missing deck: $deckPath" }
if (Test-Path -LiteralPath $pdfPath) { throw "Use a new revision. Output already exists: $pdfPath" }
New-Item -ItemType Directory -Force -Path $renderPath | Out-Null
$application = $null
$deck = $null
$powerPointWasRunning = [bool](Get-Process -Name POWERPNT -ErrorAction SilentlyContinue)
try {
  $application = New-Object -ComObject PowerPoint.Application
  $deck = $application.Presentations.Open($deckPath, $true, $false, $false)
  # ppSaveAsPDF = 32. SaveAs writes the separate PDF, leaving the PPTX bytes intact.
  $deck.SaveAs($pdfPath, 32)
  $deck.Export($renderPath, 'PNG', 1600, 900)
  $result = [ordered]@{
    renderer = 'Microsoft PowerPoint COM'
    version = $application.Version
    openedReadOnly = $true
    slides = $deck.Slides.Count
    input = $deckPath
    pdf = $pdfPath
    rendered = $renderPath
    renderedWidth = 1600
    renderedHeight = 900
  }
  $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path (Split-Path $renderPath -Parent) 'powerpoint-export.json') -Encoding utf8
  $result | ConvertTo-Json -Compress
} finally {
  if ($deck) { $deck.Close() }
  if ($application -and !$powerPointWasRunning -and $application.Presentations.Count -eq 0) { $application.Quit() }
  if ($deck) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($deck) }
  if ($application) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($application) }
}
& $RuntimePython (Join-Path $PSScriptRoot 'add-presentation-pdf-links.py') $pdfPath
if ($LASTEXITCODE -ne 0) { throw 'PDF link annotation failed.' }
