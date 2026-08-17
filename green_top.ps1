Add-Type -AssemblyName System.Drawing
$bmp2=[System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\full_now.png')
# scan rows 600..640 for green border pixels across x 440..1140
for ($y=600; $y -le 650; $y+=1) {
  $greencount=0
  for ($x=440; $x -le 1140; $x+=2) {
    $c=$bmp2.GetPixel($x,$y)
    if ([Math]::Abs($c.R-7) -le 15 -and [Math]::Abs($c.G-193) -le 15 -and [Math]::Abs($c.B-96) -le 15) { $greencount++ }
  }
  if ($greencount -gt 0) { Write-Output "y=$y green pixels: $greencount" }
}
$bmp2.Dispose()
