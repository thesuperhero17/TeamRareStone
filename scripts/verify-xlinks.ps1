param([string]$OutCsv)
# For every artwork with an X-link sidecar: fetch the tweet's media via the
# public embed endpoint, compare each image to (a) the linked artwork and
# (b) every artwork on the site. Flags links whose tweet image does not
# match its own artwork, or matches some other artwork better.
# NOTE: PowerShell variable names are case-insensitive -- every name below
# is distinct ignoring case.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
public static class SigTools {
  public static double Diff(double[] a, double[] b) {
    double s = 0; for (int i = 0; i < a.Length; i++) { s += System.Math.Abs(a[i] - b[i]); }
    return System.Math.Round(s / a.Length, 1);
  }
  public static double[] Make(System.Drawing.Image img, int size) {
    using (var bmp = new System.Drawing.Bitmap(size, size))
    using (var g = System.Drawing.Graphics.FromImage(bmp)) {
      g.Clear(System.Drawing.Color.White);
      g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBilinear;
      g.DrawImage(img, 0, 0, size, size);
      var v = new double[size * size * 3]; int k = 0;
      for (int y = 0; y < size; y++) for (int x = 0; x < size; x++) {
        var c = bmp.GetPixel(x, y); v[k++] = c.R; v[k++] = c.G; v[k++] = c.B;
      }
      return v;
    }
  }
}
'@ -ReferencedAssemblies System.Drawing

$root = 'D:\Cluade\rarestone-portfolio'
$sigSize = 24

$siteSigs = @{}
$allJpgs = Get-ChildItem $root -Directory | Where-Object { $_.Name -match '^\d{2}_' } | ForEach-Object { Get-ChildItem $_.FullName -File -Filter *.jpg }
foreach ($jf in $allJpgs) {
  $im = [System.Drawing.Image]::FromFile($jf.FullName)
  $siteSigs["$($jf.Directory.Name)/$($jf.Name)"] = [SigTools]::Make($im, $sigSize)
  $im.Dispose()
}
Write-Host "site signatures: $($siteSigs.Count)"

$web = New-Object System.Net.WebClient
$results = @()
$linkFiles = @(Get-ChildItem $root -Directory | Where-Object { $_.Name -match '^\d{2}_' } | ForEach-Object { Get-ChildItem $_.FullName -File -Filter *.txt } | Sort-Object FullName)
$done = 0
foreach ($lf in $linkFiles) {
  $done++
  $artKey = "$($lf.Directory.Name)/$($lf.BaseName).jpg"
  $tweetUrl = (Get-Content $lf.FullName -TotalCount 1).Trim()
  $res = [ordered]@{ Artwork=$artKey; Tweet=$tweetUrl; Media=0; OwnDiff=''; BestOther=''; BestOtherDiff=''; Status='' }
  if (-not $siteSigs.ContainsKey($artKey)) { $res.Status = 'NO JPG FOR THIS TXT'; $results += [PSCustomObject]$res; continue }
  if ($tweetUrl -notmatch '/status/(\d+)') { $res.Status = 'BAD URL'; $results += [PSCustomObject]$res; continue }
  $tweetId = $Matches[1]
  try {
    $info = Invoke-RestMethod "https://cdn.syndication.twimg.com/tweet-result?id=$tweetId&lang=en&token=a" -UseBasicParsing
  } catch { $res.Status = 'FETCH FAILED'; $results += [PSCustomObject]$res; Start-Sleep -Milliseconds 500; continue }
  $mediaList = @()
  if ($info.mediaDetails) { $mediaList = @($info.mediaDetails | ForEach-Object { [PSCustomObject]@{ Kind=$_.type; Src=$_.media_url_https } }) }
  elseif ($info.photos) { $mediaList = @($info.photos | ForEach-Object { [PSCustomObject]@{ Kind='photo'; Src=$_.url } }) }
  $res.Media = $mediaList.Count
  if ($mediaList.Count -eq 0) { $res.Status = 'NO MEDIA (deleted/protected?)'; $results += [PSCustomObject]$res; continue }

  $ownSig = $siteSigs[$artKey]
  $bestOwnDiff = 9999.0; $bestOtherDiff = 9999.0; $bestOtherKey = ''; $kinds = @()
  foreach ($md in $mediaList) {
    $kinds += $md.Kind
    $dl = $md.Src
    if ($dl -match 'pbs\.twimg\.com/media/') { $dl = ($dl -replace '\.(jpg|png)$', '') + '?format=jpg&name=small' }
    try { $bytes = $web.DownloadData($dl) } catch { continue }
    $stream = New-Object System.IO.MemoryStream(,$bytes)
    $tweetImg = [System.Drawing.Image]::FromStream($stream)
    $mediaSig = [SigTools]::Make($tweetImg, $sigSize)
    $tweetImg.Dispose(); $stream.Dispose()
    $dOwn = [SigTools]::Diff($mediaSig, $ownSig)
    if ($dOwn -lt $bestOwnDiff) { $bestOwnDiff = $dOwn }
    foreach ($otherKey in $siteSigs.Keys) {
      if ($otherKey -eq $artKey) { continue }
      $dOther = [SigTools]::Diff($mediaSig, $siteSigs[$otherKey])
      if ($dOther -lt $bestOtherDiff) { $bestOtherDiff = $dOther; $bestOtherKey = $otherKey }
    }
  }
  $res.OwnDiff = $bestOwnDiff; $res.BestOther = $bestOtherKey; $res.BestOtherDiff = $bestOtherDiff
  $hasVideo = @($kinds | Where-Object { $_ -ne 'photo' }).Count -gt 0
  if ($bestOwnDiff -le 8 -and $bestOwnDiff -lt $bestOtherDiff) { $res.Status = 'OK' }
  elseif ($bestOtherDiff -lt $bestOwnDiff) { $res.Status = 'MATCHES ANOTHER ARTWORK BETTER' }
  elseif ($hasVideo) { $res.Status = 'CHECK (video/gif thumbnail)' }
  else { $res.Status = 'CHECK (weak match)' }
  $results += [PSCustomObject]$res
  if ($done % 25 -eq 0) { Write-Host "  $done / $($linkFiles.Count)" }
  Start-Sleep -Milliseconds 300
}
$results | Export-Csv $OutCsv -NoTypeInformation -Encoding UTF8
Write-Host ""
$results | Group-Object Status | ForEach-Object { Write-Host ("{0}: {1}" -f $_.Name, $_.Count) }
