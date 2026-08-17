Add-Type -AssemblyName System.Drawing
$bmp2=[System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\full_now.png')
foreach ($xx in @(500,700,900)) {
  Write-Output "=== x=$xx y=720..875 ==="
  $prev=$null
  for ($y=720; $y -le 874; $y+=1) {
    $c=$bmp2.GetPixel($xx,$y)
    $key="$($c.R),$($c.G),$($c.B)"
    if ($key -ne $prev) { Write-Output "y=$y rgb=($key)"; $prev=$key }
  }
}
$bmp2.Dispose()
