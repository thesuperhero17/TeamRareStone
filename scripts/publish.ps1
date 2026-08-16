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
Write-Host "Step 1/3: Rebuilding the artwork list..." -ForegroundColor Cyan
& (Join-Path $root "scripts\build-manifest.ps1")

Write-Host ""
Write-Host "Step 2/3: Checking what changed..." -ForegroundColor Cyan
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
Write-Host "Step 3/3: Publishing to GitHub..." -ForegroundColor Cyan
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
Write-Host "  https://thesuperhero17.github.io/TeamRareStone/" -ForegroundColor Green
Write-Host ""
Read-Host "Press Enter to close"
