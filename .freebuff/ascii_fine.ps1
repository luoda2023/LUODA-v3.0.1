Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$L = 570; $T = 150; $W = 500; $H = 90
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($L, $T, 0, 0, (New-Object System.Drawing.Size($W, $H)))
$step = 2
for ($y = 0; $y -lt $H; $y += $step) {
  $line = ''
  for ($x = 0; $x -lt $W; $x += $step) {
    $c = $bmp.GetPixel($x, $y)
    if ($c.R -gt 248 -and $c.G -gt 248 -and $c.B -gt 248) { $ch = '.' }
    elseif ($c.R -lt 90 -and $c.G -lt 90 -and $c.B -lt 90) { $ch = '#' }
    elseif ($c.G -gt 130 -and $c.R -lt 110) { $ch = 'G' }
    elseif ($c.R -gt 150 -and $c.G -gt 150 -and $c.B -gt 150) { $ch = '-' }
    elseif ($c.R -lt 140 -and $c.G -lt 140 -and $c.B -lt 140) { $ch = '+' }
    else { $ch = 'o' }
    $line += $ch
  }
  Write-Output ("y={0}: {1}" -f ($T + $y), $line)
}
$g.Dispose(); $bmp.Dispose()
