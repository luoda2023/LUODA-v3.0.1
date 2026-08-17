Add-Type -AssemblyName System.Drawing
$bmp2=[System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\focus_check.png')
foreach ($yy in @(820, 830, 840, 850, 860)) {
  Write-Output "=== y=$yy x=1000..1145 ==="
  $prev=$null
  for ($x=1000; $x -le 1145; $x+=3) {
    $c=$bmp2.GetPixel($x,$yy)
    $key="$($c.R),$($c.G),$($c.B)"
    if ($key -ne $prev) { Write-Output "x=$x rgb=($key)"; $prev=$key }
  }
}
$bmp2.Dispose()
