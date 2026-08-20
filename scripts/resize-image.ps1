<#
  Pick one image file and convert it to a display-ready JPG:
  - Caps the long edge at $MaxLongEdge px (only shrinks, never enlarges)
  - Re-encodes as JPEG at quality $JpegQuality
  - Saves next to the source file, same name, .jpg extension
  Run with no arguments for the friendly picker -- just double-click
  resize-image.bat next to this file. Loops so you can do several in a row.
#>
param(
  [int]$MaxLongEdge = 2000,
  [int]$JpegQuality = 85
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Convert-OneImage {
  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  $dlg.Title = "Pick an image to resize + convert"
  $dlg.Filter = "Image files (*.png;*.jpg;*.jpeg)|*.png;*.jpg;*.jpeg|All files (*.*)|*.*"
  $dlg.InitialDirectory = "D:\새로시작"
  if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $false }

  $srcPath = $dlg.FileName
  $srcInfo = Get-Item $srcPath
  $outPath = [System.IO.Path]::ChangeExtension($srcPath, ".jpg")

  $img = [System.Drawing.Image]::FromFile($srcPath)
  $origW = $img.Width
  $origH = $img.Height
  $longEdge = [Math]::Max($origW, $origH)

  if ($longEdge -gt $MaxLongEdge) {
    $scale = $MaxLongEdge / $longEdge
    $newW = [int][Math]::Round($origW * $scale)
    $newH = [int][Math]::Round($origH * $scale)
  } else {
    $newW = [int]$origW
    $newH = [int]$origH
  }

  # Flatten onto white first (JPEG has no alpha channel -- avoids black/garbled
  # output if the source PNG has any transparency) and resize in one pass.
  $bmp = [System.Drawing.Bitmap]::new($newW, $newH)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([System.Drawing.Color]::White)
  $g.DrawImage($img, 0, 0, $newW, $newH)
  $g.Dispose()
  $img.Dispose()

  $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
  $encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
  $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [int64]$JpegQuality)
  $bmp.Save($outPath, $jpegCodec, $encParams)
  $bmp.Dispose()

  $outInfo = Get-Item $outPath
  Write-Host ""
  Write-Host "  Done: $($srcInfo.Name)" -ForegroundColor Green
  Write-Host "    ${origW}x${origH} -> ${newW}x${newH}"
  Write-Host ("    {0:N1} MB -> {1:N1} MB" -f ($srcInfo.Length/1MB), ($outInfo.Length/1MB))
  Write-Host "    Saved: $outPath"
  return $true
}

Write-Host ""
Write-Host "=== TeamRareStone -- Resize + Convert Image ===" -ForegroundColor Yellow
Write-Host "  Long edge capped at $MaxLongEdge px, JPEG quality $JpegQuality."

do {
  $ok = Convert-OneImage
  if (-not $ok) { break }
  Write-Host ""
  $again = Read-Host "  Convert another? (Y/n)"
} while ($again -notmatch '^n')

Write-Host ""
Read-Host "  Press Enter to close"
