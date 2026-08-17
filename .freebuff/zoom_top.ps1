Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$L = 570; $T = 89
$W = 470; $H = 200
$scale = 2
$bmp = New-Object System.Drawing.Bitmap(($W * $scale), ($H * $scale))
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($L, $T, 0, 0, (New-Object System.Drawing.Size($W, $H)))
# Save zoomed
$bmp.Save("J:\codex-work\LUODA-v3.0.1\.freebuff\zoom_top.png", [System.Drawing.Imaging.ImageFormat]::Png)
# Scan for green-ish accent pixels (#107C41) within the raw region
$bmp2 = New-Object System.Drawing.Bitmap($W, $H)
$g2 = [System.Drawing.Graphics]::FromImage($bmp2)
$g2.CopyFromScreen($L, $T, 0, 0, (New-Object System.Drawing.Size($W, $H)))
$count = 0
for ($x = 0; $x -lt $W; $x += 2) {
  for ($y = 0; $y -lt $H; $y += 2) {
    $c = $bmp2.GetPixel($x, $y)
    if ($c.R -gt 8 -and $c.R -lt 60 -and $c.G -gt 100 -and $c.G -lt 160 -and $c.B -gt 40 -and $c.B -lt 100) {
      if ($count -lt 20) { Write-Host ("green at x={0} y={1} rgb={2},{3},{4}" -f $x, $y, $c.R, $c.G, $c.B) }
      $count++
    }
  }
}
Write-Host "total green-ish pixels: $count"
$g.Dispose(); $bmp.Dispose(); $g2.Dispose(); $bmp2.Dispose()
