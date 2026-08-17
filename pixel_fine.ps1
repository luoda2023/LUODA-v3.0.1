Add-Type -AssemblyName System.Drawing
$bmp2=[System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\focus_check.png')
$prev = $null
for ($y = 600; $y -le 870; $y += 1) {
  $c = $bmp2.GetPixel(700, $y)
  $key = "$($c.R),$($c.G),$($c.B)"
  if ($key -ne $prev) { Write-Output ("y={0} rgb=({1})" -f $y, $key); $prev = $key }
}
$bmp2.Dispose()
