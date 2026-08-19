<#
  Scans the category-thumbs/ and numbered category folders and writes
  data/manifest.json — the single file the live site reads to know what
  categories and artworks exist. Run this after adding/removing/reordering
  any images, then commit + push data/manifest.json along with the images.

  Convention (see scripts/insert-image.ps1 for the folder-editing side):
    category-thumbs/NN_Label.jpg   -> one portal banner per category
    NN_Label/NNNN_Title.jpg        -> that category's artworks
    NN_Label/NNNN_Title_R18.jpg    -> same, flagged mature by the artist
    NN_Label/NNNN_Title.txt        -> optional, first line = that artwork's
                                       X (Twitter) post URL. Same basename as
                                       the jpg (include _R18 if present). Not
                                       required -- artworks without one just
                                       don't show an X link in the lightbox.
  Sort order within a category: higher NNNN = newer = shown first.
#>
param(
  [string]$Root = "D:\Cluade\rarestone-portfolio"
)

$thumbDir = Join-Path $Root "category-thumbs"
$dataDir = Join-Path $Root "data"
New-Item -ItemType Directory -Force $dataDir | Out-Null

# --- categories, from category-thumbs/ (skip _wide companions, handled below) ---
$thumbFiles = Get-ChildItem -Path $thumbDir -File -Filter "*.jpg" |
  Where-Object { $_.BaseName -notmatch '_wide$' } | Sort-Object Name
$categories = @()
foreach ($f in $thumbFiles) {
  if ($f.BaseName -match '^(\d{2})_(.+)$') {
    $num = $Matches[1]
    $label = $Matches[2]
    $key = $label.ToLower()
    $widePath = Join-Path $thumbDir "$($f.BaseName)_wide.jpg"
    $cat = [PSCustomObject]@{
      key = $key
      label = $label
      banner = "category-thumbs/$($f.Name)"
      isAll = ($key -eq "all")
    }
    if (Test-Path $widePath) {
      $cat | Add-Member -NotePropertyName bannerWide -NotePropertyValue "category-thumbs/$($f.BaseName)_wide.jpg"
    }
    $categories += $cat
  }
}
$wideCount = ($categories | Where-Object { $_.PSObject.Properties.Name -contains 'bannerWide' }).Count
Write-Output "Categories found: $($categories.Count) ($wideCount with a _wide mobile banner)"

# --- artworks, from each NN_Label folder (skip 'all', it has no real folder) ---
$artworks = @()
foreach ($cat in $categories) {
  if ($cat.isAll) { continue }
  $folder = Get-ChildItem -Path $Root -Directory | Where-Object { $_.Name -match "^\d{2}_$([regex]::Escape($cat.label))$" } | Select-Object -First 1
  if (-not $folder) { Write-Warning "No folder found for category '$($cat.label)' -- skipping"; continue }

  $files = Get-ChildItem -Path $folder.FullName -File -Filter "*.jpg" |
    Where-Object { $_.Name -match '^\d{4}_' } |
    Sort-Object Name -Descending   # higher number = newer = first

  foreach ($f in $files) {
    $isR18 = $f.BaseName -match '_R18$'
    $title = $f.BaseName -replace '^\d{4}_', '' -replace '_R18$', ''
    $art = [PSCustomObject]@{
      src   = "$($folder.Name)/$($f.Name)"
      title = $title
      cat   = $cat.key
      r18   = $isR18
    }
    $xLinkPath = Join-Path $folder.FullName "$($f.BaseName).txt"
    if (Test-Path $xLinkPath) {
      $xLink = (Get-Content -Path $xLinkPath -TotalCount 1 -Encoding UTF8).Trim()
      if ($xLink) { $art | Add-Member -NotePropertyName xLink -NotePropertyValue $xLink }
    }
    $artworks += $art
  }
  Write-Output "  $($cat.label): $($files.Count) artworks"
}

$manifest = [PSCustomObject]@{
  categories  = $categories | Select-Object key, label, banner, bannerWide
  artworks    = $artworks
}

$outPath = Join-Path $dataDir "manifest.json"
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $outPath -Encoding UTF8
Write-Output ""
Write-Output "Wrote $outPath ($($artworks.Count) artworks, $($categories.Count) categories)"
