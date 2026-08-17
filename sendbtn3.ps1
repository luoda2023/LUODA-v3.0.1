Add-Type -AssemblyName System.Drawing
$bmp2=[System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\focus_check.png')
$prev=$null
for ($x=880; $x -le 1145; $x+=2) {
  $c=$bmp2.GetPixel($x,840)
  $key="$($c.R),$($c.G),$($c.B)"
  if ($key -ne $prev) { Write-Output "y=840 x=$x rgb=($key)"; $prev=$key }
}
$bmp2.Dispose()
