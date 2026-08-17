Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$L = 570; $T = 175; $W = 520; $H = 95
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($L, $T, 0, 0, (New-Object System.Drawing.Size($W, $H)))
$step = 4
for ($y = 0; $y -lt $H; $y += $step) {
  $line = ''
  for ($x = 0; $x -lt $W; $x += $step) {
    $c = $bmp.GetPixel($x, $y)
    if ($c.R -gt 248 -and $c.G -gt 248 -and $c.B -gt 248) { $ch = '.' }
    elseif ($c.R -lt 70 -and $c.G -lt 70 -and $c.B -lt 70) { $ch = '#' }
    elseif ($c.G -gt 130 -and $c.R -lt 110) { $ch = 'G' }
    elseif ($c.R -gt 150 -and $c.G -gt 150 -and $c.B -gt 150) { $ch = '-' }
    elseif ($c.R -lt 130 -and $c.G -lt 130 -and $c.B -lt 130) { $ch = '+' }
    else { $ch = 'o' }
    $line += $ch
  }
  Write-Output ("y={0}: {1}" -f ($T + $y), $line)
}
$g.Dispose(); $bmp.Dispose()
