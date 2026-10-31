<#
  One-click publish: rebuild the manifest, then commit + push everything
  to GitHub. This is the only script you need to run after adding,
  removing, or reordering images -- just double-click publish.bat.
#>
$root = "D:\Cluade\rarestone-portfolio"
Set-Location $root

Write-Host ""
Write-Host "=== TeamRareStone -- Publish ===" -ForegroundColor Yellow

Write-Host ""
Write-Host "Step 1/4: Rebuilding the artwork list..." -ForegroundColor Cyan
& (Join-Path $root "scripts\build-manifest.ps1")

# Grid thumbnails (small pre-shrunk copies, so 100%-scale monitors don't show
# jagged/moire thumbnails) + face position for each artwork (data/focus.json).
# Needs the separate Python environment D:\Cluade\tools\face-venv (outside the
# repo on purpose). Only new or changed artworks are processed.
Write-Host ""
Write-Host "Step 2/4: Making grid thumbnails and finding faces..." -ForegroundColor Cyan
$py = "D:\Cluade\tools\face-venv\Scripts\python.exe"
if (Test-Path $py) {
  & $py -I (Join-Path $root "scripts\make-thumbs.py")
  if ($LASTEXITCODE -ne 0) { Write-Host "  Thumbnail step failed -- the site falls back to full images for new artwork." -ForegroundColor Yellow }
} else {
  Write-Host "  Skipped: $py not found -- new artwork shows full images in the grid until it exists." -ForegroundColor Yellow
}

# Safety net: two artworks that are byte-identical files means one of them
# got overwritten by the other (happened to 15 same-name redraws once --
# helm/Helm, Diana/diana, ... -- and went unnoticed for over a month).
$artFiles = Get-ChildItem $root -Directory | Where-Object { $_.Name -match '^\d{2}_' } |
  ForEach-Object { Get-ChildItem $_.FullName -File -Filter "*.jpg" }
$dupes = $artFiles | Group-Object { (Get-FileHash $_.FullName -Algorithm MD5).Hash } | Where-Object Count -gt 1
if ($dupes) {
  Write-Host ""
  Write-Host "  WARNING: these artworks are the exact same image file:" -ForegroundColor Red
  foreach ($d in $dupes) { Write-Host ("    - " + (($d.Group | ForEach-Object { "$($_.Directory.Name)/$($_.Name)" }) -join "  ==  ")) -ForegroundColor Red }
  Write-Host "  One of each pair was probably overwritten by mistake." -ForegroundColor Red
  $answer = Read-Host "  Publish anyway? (y/N)"
  if ($answer -ne 'y') { Write-Host "  Stopped. Nothing was published."; Read-Host "Press Enter to close"; exit 1 }
}

Write-Host ""
Write-Host "Step 3/4: Checking what changed..." -ForegroundColor Cyan
git add -A | Out-Null
$changes = git status --short
if (-not $changes) {
  Write-Host "  Nothing changed -- the site is already up to date." -ForegroundColor Green
  Read-Host "Press Enter to close"
  exit 0
}

$added    = ($changes | Where-Object { $_ -match '^A ' }).Count
$modified = ($changes | Where-Object { $_ -match '^M ' }).Count
$deleted  = ($changes | Where-Object { $_ -match '^D ' }).Count
$renamed  = ($changes | Where-Object { $_ -match '^R ' }).Count
Write-Host "  +$added added, ~$modified changed, -$deleted removed, $renamed renamed" -ForegroundColor Gray

$stamp = Get-Date -Format "yyyy-MM-dd HH:mm"
$msg = "Update artwork -- $stamp"

Write-Host ""
Write-Host "Step 4/4: Publishing to GitHub..." -ForegroundColor Cyan
git commit -m $msg | Out-Null
$pushResult = git push 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Host ""
  Write-Host "  Push failed:" -ForegroundColor Red
  Write-Host "  $pushResult"
  Read-Host "Press Enter to close"
  exit 1
}

Write-Host ""
Write-Host "  Done! Live in about a minute at:" -ForegroundColor Green
Write-Host "  https://teamrarestone.art/" -ForegroundColor Green
Write-Host ""
Read-Host "Press Enter to close"
