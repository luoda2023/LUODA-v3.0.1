Add-Type -AssemblyName System.Drawing
$bmp2=[System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\focus_check.png')
# scan bottom-right region for the send button: find rect of 0xFFF0F0F0 or green 7,193,96
Write-Output '=== scan y 700..860, x 1050..1240 for send button colors ==='
$prev=$null
for ($y=700; $y -le 860; $y+=2) {
  $c=$bmp2.GetPixel(1100,$y)
  $key="$($c.R),$($c.G),$($c.B)"
  if ($key -ne $prev) { Write-Output "x=1100 y=$y rgb=($key)"; $prev=$key }
}
$prev=$null
for ($x=1050; $x -le 1240; $x+=2) {
  $c=$bmp2.GetPixel($x,749)
  $key="$($c.R),$($c.G),$($c.B)"
  if ($key -ne $prev) { Write-Output "y=749 x=$x rgb=($key)"; $prev=$key }
}
$bmp2.Dispose()
