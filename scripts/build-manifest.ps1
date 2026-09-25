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

# --- "date added" tracking (2026-08-21 convention) ---
# File timestamps (created/modified) aren't reliable as an upload-date proxy --
# a bulk resize or a folder migration touches every file at once and wipes out
# any real per-artwork history. So instead we keep our own small ledger here:
# the first time build-manifest.ps1 ever sees a given artwork, it stamps that
# artwork with the real current moment and remembers it forever after (existing
# stamps are never overwritten). Artworks from before this convention existed
# have no stamp at all -- the site treats "no stamp" as legacy/undated and
# falls back to the old category-grouped ordering for those. See the
# project-rarestone-portfolio memory for why (a user question about sorting
# the All tab by upload date, and file-timestamp-as-proxy turning out unusable).
$datesPath = Join-Path $dataDir "added-dates.json"
$addedDates = [ordered]@{}
if (Test-Path $datesPath) {
  $loaded = Get-Content $datesPath -Raw | ConvertFrom-Json
  foreach ($p in $loaded.PSObject.Properties) { $addedDates[$p.Name] = $p.Value }
}
# Keys are "cat|title|N", N = which same-titled artwork this is within its
# category. Note both hashtables here are case-INsensitive (PowerShell default),
# so "Joanne" and "joanne" share one title slot -- intentional, since Windows
# PowerShell's ConvertFrom-Json can't load keys that differ only by case.
# N is counted OLDEST-first (lowest NNNN = 1), so a newly appended redraw of an
# existing character gets a fresh N instead of taking over the older piece's
# key. (It used to count newest-first, and a new 0048_Joanne inherited the old
# 0014_joanne's 2025 date -- it vanished from the top of the All tab.)
$dateKeyCounts = @{}
function Get-DateKey($catKey, $title) {
  $base = "$catKey|$title"
  if (-not $dateKeyCounts.ContainsKey($base)) { $dateKeyCounts[$base] = 0 }
  $dateKeyCounts[$base]++
  return "$base|$($dateKeyCounts[$base])"
}

# X (Twitter) status IDs are Snowflake IDs -- they encode the real post
# timestamp. When an artwork has a linked X post, that's a far more precise
# "when was this actually shared" signal than our own first-seen ledger, so
# it's used to backfill legacy (pre-tracking) entries too, not just new ones.
function Get-XPostDate($xLink) {
  if ($xLink -match '/status/(\d+)') {
    $id = [int64]$Matches[1]
    $ms = ($id -shr 22) + 1288834974657
    return [DateTimeOffset]::FromUnixTimeMilliseconds($ms).UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss")
  }
  return $null
}

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

  # Assign ledger keys oldest-first (see Get-DateKey above for why).
  $dateKeys = @{}
  foreach ($f in ($files | Sort-Object Name)) {
    $t = $f.BaseName -replace '^\d{4}_', '' -replace '_R18$', ''
    $dateKeys[$f.Name] = Get-DateKey $cat.key $t
  }

  foreach ($f in $files) {
    $isR18 = $f.BaseName -match '_R18$'
    $title = $f.BaseName -replace '^\d{4}_', '' -replace '_R18$', ''
    $art = [PSCustomObject]@{
      src   = "$($folder.Name)/$($f.Name)"
      title = $title
      cat   = $cat.key
      r18   = $isR18
    }
    $xLink = $null
    $xLinkPath = Join-Path $folder.FullName "$($f.BaseName).txt"
    if (Test-Path $xLinkPath) {
      $xLink = (Get-Content -Path $xLinkPath -TotalCount 1 -Encoding UTF8).Trim()
      if ($xLink) { $art | Add-Member -NotePropertyName xLink -NotePropertyValue $xLink }
    }

    $dateKey = $dateKeys[$f.Name]
    $xPostDate = if ($xLink) { Get-XPostDate $xLink } else { $null }
    if ($xPostDate) {
      # The X post timestamp is ground truth whenever we have one, so it always
      # wins -- including over an older "now" stamp from before the .txt was added.
      $addedDates[$dateKey] = $xPostDate
    } elseif (-not $addedDates.Contains($dateKey)) {
      # Never seen before and no X link -> genuinely new artwork, stamp "now".
      $addedDates[$dateKey] = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    }
    if ($addedDates[$dateKey]) {
      $art | Add-Member -NotePropertyName addedDate -NotePropertyValue $addedDates[$dateKey]
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
$addedDates | ConvertTo-Json -Depth 3 | Set-Content -Path $datesPath -Encoding UTF8
Write-Output ""
Write-Output "Wrote $outPath ($($artworks.Count) artworks, $($categories.Count) categories)"
