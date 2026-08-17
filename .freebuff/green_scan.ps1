Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$L = 570; $T = 89; $W = 1220; $H = 974
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($L, $T, 0, 0, (New-Object System.Drawing.Size($W, $H)))
$points = New-Object System.Collections.Generic.List[string]
for ($y = 0; $y -lt $H; $y += 2) {
  for ($x = 0; $x -lt $W; $x += 2) {
    $c = $bmp.GetPixel($x, $y)
    if ($c.R -ge 5 -and $c.R -le 70 -and $c.G -ge 90 -and $c.G -le 160 -and $c.B -ge 30 -and $c.B -le 110) {
      $points.Add("$x,$y")
    }
  }
}
Write-Host ("green pixels: " + $points.Count)
# Print first 40 with counts per y band to find clusters
$bands = @{}
foreach ($p in $points) {
  $parts = $p.Split(',')
  $yy = [int]$parts[1]
  $band = [int]($yy / 40)
  if (-not $bands.ContainsKey($band)) { $bands[$band] = 0 }
  $bands[$band]++
}
$sorted = $bands.GetEnumerator() | Sort-Object Name
foreach ($b in $sorted) {
  Write-Host ("y-band {0}-{1}: {2} px" -f ($b.Name * 40), ($b.Name * 40 + 40), $b.Value)
}
$g.Dispose(); $bmp.Dispose()
