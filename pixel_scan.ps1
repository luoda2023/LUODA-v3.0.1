Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\main_after_paste.png')
$bmp = New-Object System.Drawing.Bitmap($img.Width, $img.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.DrawImage($img, 0, 0, $img.Width, $img.Height)
$g.Dispose(); $img.Dispose()
Write-Output "bitmap size: $($bmp.Width)x$($bmp.Height)"
Write-Output '=== vertical x=500 y=600..860 ==='
$prev = $null
for ($y = 600; $y -le 860; $y += 3) {
  $c = $bmp.GetPixel(500, $y)
  $key = "$($c.R),$($c.G),$($c.B)"
  if ($key -ne $prev) { Write-Output ("y={0} rgb=({1})" -f $y, $key); $prev = $key }
}
Write-Output '=== horizontal y=706 x=430..1250 ==='
$prev = $null
for ($x = 430; $x -le 1250; $x += 8) {
  $c = $bmp.GetPixel($x, 706)
  $key = "$($c.R),$($c.G),$($c.B)"
  if ($key -ne $prev) { Write-Output ("x={0} rgb=({1})" -f $x, $key); $prev = $key }
}
Write-Output '=== horizontal y=647 x=430..1250 ==='
$prev = $null
for ($x = 430; $x -le 1250; $x += 8) {
  $c = $bmp.GetPixel($x, 647)
  $key = "$($c.R),$($c.G),$($c.B)"
  if ($key -ne $prev) { Write-Output ("x={0} rgb=({1})" -f $x, $key); $prev = $key }
}
$bmp.Dispose()
