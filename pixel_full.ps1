Add-Type -AssemblyName System.Drawing
$bmp2=[System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\focus_check.png')
Write-Output "size $($bmp2.Width)x$($bmp2.Height)"
foreach ($xx in @(500, 700, 900, 1100)) {
  Write-Output "=== vertical x=$xx y=90..870 ==="
  $prev = $null
  for ($y = 90; $y -le 870; $y += 3) {
    $c = $bmp2.GetPixel($xx, $y)
    $key = "$($c.R),$($c.G),$($c.B)"
    if ($key -ne $prev) { Write-Output ("y={0} rgb=({1})" -f $y, $key); $prev = $key }
  }
}
$bmp2.Dispose()
