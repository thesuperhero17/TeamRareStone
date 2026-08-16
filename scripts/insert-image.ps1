<#
  Insert one or more images into a category folder at a specific position.
  Run with no arguments for a friendly, menu-driven mode (recommended --
  just double-click add-image.bat next to this file).
  Parameters below still work for scripted/one-line use.
#>
param(
  [string]$CategoryPath,
  [int]$Position = 0,
  [string[]]$Files,
  [switch]$DryRun
)

$root = "D:\Cluade\rarestone-portfolio"
$Interactive = (-not $CategoryPath) -or ($Position -eq 0)

function Show-Menu-And-Pick-Category {
  $cats = Get-ChildItem -Path $root -Directory | Where-Object { $_.Name -match '^\d{2}_' } | Sort-Object Name
  Write-Host ""
  Write-Host "  Which category are you adding image(s) to?" -ForegroundColor Cyan
  for ($i = 0; $i -lt $cats.Count; $i++) {
    Write-Host ("    {0}) {1}" -f ($i+1), $cats[$i].Name)
  }
  Write-Host ""
  do {
    $pick = Read-Host "  Enter a number (1-$($cats.Count))"
  } until ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $cats.Count)
  return $cats[[int]$pick - 1].FullName
}

if ($Interactive) {
  Write-Host ""
  Write-Host "=== TeamRareStone -- Add Image ===" -ForegroundColor Yellow

  if (-not $CategoryPath) {
    $CategoryPath = Show-Menu-And-Pick-Category
  }

  $pending = Get-ChildItem -Path $CategoryPath -File | Where-Object { $_.Name -notmatch '^\d{4}_' } | Sort-Object Name
  if (-not $pending -or $pending.Count -eq 0) {
    Write-Host ""
    Write-Host "  No new (unnumbered) files found in:" -ForegroundColor Red
    Write-Host "    $CategoryPath"
    Write-Host "  Drag your image file into that folder first, then run this again."
    Write-Host ""
    Read-Host "  Press Enter to close"
    exit 0
  }

  Write-Host ""
  Write-Host "  Found $($pending.Count) new file(s) waiting:" -ForegroundColor Cyan
  $pending | ForEach-Object { Write-Host "    - $($_.Name)" }
  $Files = $pending.Name

  $existingCount = (Get-ChildItem -Path $CategoryPath -File | Where-Object { $_.Name -match '^\d{4}_' }).Count
  $pronoun = if ($Files.Count -gt 1) { "they" } else { "it" }
  Write-Host ""
  Write-Host "  Where should $pronoun go?" -ForegroundColor Cyan
  Write-Host "    - Type a position number (e.g. 18) to insert there and push existing ones back"
  Write-Host "    - Or just press Enter to add at the very end (position $($existingCount + 1))"
  $posInput = Read-Host "  Position"
  if ([string]::IsNullOrWhiteSpace($posInput)) {
    $Position = $existingCount + 1
  } else {
    $Position = [int]$posInput
  }
}

# ---- from here on, logic is identical whether interactive or parameterized ----
if (-not (Test-Path $CategoryPath)) { Write-Host "Category folder not found: $CategoryPath" -ForegroundColor Red; if($Interactive){Read-Host "Press Enter to close"}; exit 1 }
if (-not $Files -or $Files.Count -eq 0) {
  $Files = Get-ChildItem -Path $CategoryPath -File | Where-Object { $_.Name -notmatch '^\d{4}_' } | Sort-Object Name | Select-Object -ExpandProperty Name
}
if (-not $Files -or $Files.Count -eq 0) {
  Write-Host "No unnumbered files found to insert."
  if($Interactive){Read-Host "Press Enter to close"}
  exit 0
}

$numberedFiles = Get-ChildItem -Path $CategoryPath -File | Where-Object { $_.Name -match '^\d{4}_' }
$hashOf = @{}
foreach ($nf in $numberedFiles) { $hashOf[(Get-FileHash -Path $nf.FullName -Algorithm MD5).Hash] = $nf }

$plan = @()
foreach ($f in $Files) {
  $srcPath = Join-Path $CategoryPath $f
  if (-not (Test-Path $srcPath)) { continue }
  $h = (Get-FileHash -Path $srcPath -Algorithm MD5).Hash
  if ($hashOf.ContainsKey($h)) {
    $existing = $hashOf[$h]
    $title = ($existing.Name -replace '^\d+_', '')
    $plan += [PSCustomObject]@{ SourcePath=$existing.FullName; Title=$title; IsReposition=$true; RepositionedFrom=$existing.Name; NewRawCopy=$srcPath }
  } else {
    $title = ($f -replace '^\d+_', '')
    $plan += [PSCustomObject]@{ SourcePath=$srcPath; Title=$title; IsReposition=$false; RepositionedFrom=$null; NewRawCopy=$null }
  }
}
if ($plan.Count -eq 0) { Write-Host "Nothing to insert."; if($Interactive){Read-Host "Press Enter to close"}; exit 0 }
$insertCount = $plan.Count
$existingAtOrAfter = (Get-ChildItem -Path $CategoryPath | Where-Object { $_.Name -match '^(\d{4})_' -and [int]$Matches[1] -ge $Position }).Count

Write-Host ""
Write-Host "  Plan:" -ForegroundColor Yellow
foreach ($p in $plan) {
  if ($p.IsReposition) {
    Write-Host "    '$($p.RepositionedFrom)' is already in the folder under a different name -- repositioning it, not duplicating"
  } else {
    Write-Host "    '$(Split-Path -Leaf $p.SourcePath)' -> new image"
  }
}
Write-Host "    Existing files from position $Position onward shift back by $insertCount (affects $existingAtOrAfter file(s))"

if ($DryRun) {
  Write-Host ""; Write-Host "  (Preview only -- nothing changed.)" -ForegroundColor Green
  if($Interactive){Read-Host "Press Enter to close"}
  exit 0
}

if ($Interactive) {
  Write-Host ""
  $confirm = Read-Host "  Proceed? (Y/n)"
  if ($confirm -match '^n') { Write-Host "  Cancelled, nothing changed."; Read-Host "Press Enter to close"; exit 0 }
}

# Phase A: pull sources to temp names
$tempEntries = @()
$i = 0
foreach ($p in $plan) {
  $i++
  $ext = [System.IO.Path]::GetExtension($p.SourcePath)
  $tempPath = Join-Path $CategoryPath ("__insert_pending_{0}{1}" -f $i, $ext)
  Move-Item -Path $p.SourcePath -Destination $tempPath -Force
  if ($p.IsReposition -and (Test-Path $p.NewRawCopy)) { Remove-Item -Path $p.NewRawCopy -Force }
  $tempEntries += [PSCustomObject]@{ TempPath=$tempPath; Title=$p.Title }
}

# Phase B: shift existing files up, top-down
$toShift = Get-ChildItem -Path $CategoryPath | Where-Object { $_.Name -match '^(\d{4})_' -and [int]$Matches[1] -ge $Position } | Sort-Object Name -Descending
foreach ($f in $toShift) {
  $n = [int]($f.Name -replace '^(\d{4})_.*', '$1')
  $title = $f.Name -replace '^\d+_', ''
  $newName = "{0:0000}_{1}" -f ($n + $insertCount), $title
  Rename-Item -Path $f.FullName -NewName $newName
}

# Phase C: drop new files into their slots
$slot = $Position
foreach ($te in $tempEntries) {
  Rename-Item -Path $te.TempPath -NewName ("{0:0000}_{1}" -f $slot, $te.Title)
  $slot++
}

Write-Host ""
Write-Host "  Done! $insertCount file(s) inserted at position $Position." -ForegroundColor Green
if ($Interactive) { Read-Host "  Press Enter to close" }
