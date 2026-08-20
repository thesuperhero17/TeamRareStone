<#
  Bulk-regenerate the display JPGs in every 0N_Category folder from the
  pristine PNG originals kept in that category's Png\ subfolder.
  - Matches PNG to JPG by TITLE (the part after the NNNN_ number), not by
    number -- robust to the two folders' numbering having drifted apart.
  - Caps the long edge at $MaxLongEdge px (only shrinks, never enlarges),
    re-encodes as JPEG at quality $JpegQuality, and overwrites the JPG in
    place at its current path (same number/title it already has).
  - Never touches the PNG originals. Any JPG with no title-matching PNG is
    left untouched and listed at the end for manual follow-up.
#>
param(
  [int]$MaxLongEdge = 2000,
  [int]$JpegQuality = 85
)

Add-Type -AssemblyName System.Drawing

$root = "D:\Cluade\rarestone-portfolio"
$categories = Get-ChildItem $root -Directory | Where-Object { $_.Name -match '^\d{2}_' } | Sort-Object Name

$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
$encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [int64]$JpegQuality)

$totalOld = 0L
$totalNew = 0L
$converted = 0
$skipped = @()

Write-Host ""
Write-Host "=== Regenerate JPGs from PNG originals ===" -ForegroundColor Yellow
Write-Host "  Long edge cap: $MaxLongEdge px, JPEG quality: $JpegQuality"
Write-Host ""

foreach ($cat in $categories) {
  $pngDir = Join-Path $cat.FullName "Png"
  if (-not (Test-Path $pngDir)) { continue }

  $pngMap = @{}
  Get-ChildItem $pngDir -Filter "*.png" | ForEach-Object {
    if ($_.BaseName -match '^\d{4}_(.+)$') { $pngMap[$Matches[1]] = $_.FullName }
  }

  $jpgFiles = Get-ChildItem $cat.FullName -Filter "*.jpg"
  $catConverted = 0
  foreach ($jf in $jpgFiles) {
    if ($jf.BaseName -notmatch '^\d{4}_(.+)$') { continue }
    $title = $Matches[1]
    if (-not $pngMap.ContainsKey($title)) {
      $skipped += "$($cat.Name)/$($jf.Name)"
      continue
    }

    $oldSize = $jf.Length
    $img = [System.Drawing.Image]::FromFile($pngMap[$title])
    $origW = $img.Width; $origH = $img.Height
    $longEdge = [Math]::Max($origW, $origH)
    if ($longEdge -gt $MaxLongEdge) {
      $scale = $MaxLongEdge / $longEdge
      $newW = [int][Math]::Round($origW * $scale)
      $newH = [int][Math]::Round($origH * $scale)
    } else {
      $newW = [int]$origW
      $newH = [int]$origH
    }

    $bmp = [System.Drawing.Bitmap]::new($newW, $newH)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::White)
    $g.DrawImage($img, 0, 0, $newW, $newH)
    $g.Dispose()
    $img.Dispose()

    $bmp.Save($jf.FullName, $jpegCodec, $encParams)
    $bmp.Dispose()

    $newSize = (Get-Item $jf.FullName).Length
    $totalOld += $oldSize
    $totalNew += $newSize
    $converted++
    $catConverted++
  }
  Write-Host ("  {0}: {1} converted" -f $cat.Name, $catConverted)
}

Write-Host ""
Write-Host "  Total converted: $converted" -ForegroundColor Green
Write-Host ("  Size: {0:N1} MB -> {1:N1} MB" -f ($totalOld/1MB), ($totalNew/1MB))
if ($skipped.Count -gt 0) {
  Write-Host ""
  Write-Host "  Skipped (no title-matching PNG found):" -ForegroundColor Red
  $skipped | ForEach-Object { Write-Host "    - $_" }
}
