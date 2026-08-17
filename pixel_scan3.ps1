Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\main_after_paste.png')
$bmp = New-Object System.Drawing.Bitmap($img.Width, $img.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.DrawImage($img, 0, 0, $img.Width, $img.Height)
$g.Dispose(); $img.Dispose()
foreach ($yy in @(700, 730, 760, 780, 800, 806, 830, 860)) {
  Write-Output "=== horizontal y=$yy x=430..1150 ==="
  $prev = $null
  for ($x = 430; $x -le 1150; $x += 6) {
    $c = $bmp.GetPixel($x, $yy)
    $key = "$($c.R),$($c.G),$($c.B)"
    if ($key -ne $prev) { Write-Output ("x={0} rgb=({1})" -f $x, $key); $prev = $key }
  }
}
$bmp.Dispose()
