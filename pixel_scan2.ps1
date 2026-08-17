Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\main_after_paste.png')
$bmp = New-Object System.Drawing.Bitmap($img.Width, $img.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.DrawImage($img, 0, 0, $img.Width, $img.Height)
$g.Dispose(); $img.Dispose()
foreach ($xx in @(450, 600, 800, 1000)) {
  Write-Output "=== vertical x=$xx y=600..870 ==="
  $prev = $null
  for ($y = 600; $y -le 870; $y += 2) {
    $c = $bmp.GetPixel($xx, $y)
    $key = "$($c.R),$($c.G),$($c.B)"
    if ($key -ne $prev) { Write-Output ("y={0} rgb=({1})" -f $y, $key); $prev = $key }
  }
}
$bmp.Dispose()
