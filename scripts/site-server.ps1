<#
  Zero-cache local static file server for testing the rarestone-portfolio site
  before publishing. Serves the project root on localhost:27193, no caching
  headers, so every edit is visible on refresh with no browser cache fighting.
  Doesn't survive being closed / a machine restart -- start fresh each time
  Get-NetTCPConnection -LocalPort 27193 shows nothing listening.
#>

$root = "D:\Cluade\rarestone-portfolio"
$port = 27193

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Host "Serving $root on http://localhost:$port/"

while ($listener.IsListening) {
  $context = $listener.GetContext()
  $req = $context.Request
  $res = $context.Response
  try {
    $relPath = [System.Uri]::UnescapeDataString($req.Url.LocalPath.TrimStart('/'))
    if ($relPath -eq "") { $relPath = "index.html" }
    $filePath = Join-Path $root $relPath
    if (Test-Path -LiteralPath $filePath -PathType Leaf) {
      $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
      $ct = switch ($ext) {
        ".html" { "text/html; charset=utf-8" }
        ".css"  { "text/css; charset=utf-8" }
        ".js"   { "application/javascript; charset=utf-8" }
        ".json" { "application/json; charset=utf-8" }
        ".png"  { "image/png" }
        ".jpg"  { "image/jpeg" }
        ".jpeg" { "image/jpeg" }
        ".svg"  { "image/svg+xml" }
        default { "application/octet-stream" }
      }
      $res.Headers.Add("Cache-Control", "no-store, no-cache, must-revalidate")
      $bytes = [System.IO.File]::ReadAllBytes($filePath)
      $res.ContentType = $ct
      $res.ContentLength64 = $bytes.Length
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $res.StatusCode = 404
    }
  } catch {
    try { $res.StatusCode = 500 } catch {}
  } finally {
    try { $res.OutputStream.Close() } catch {}
  }
}
