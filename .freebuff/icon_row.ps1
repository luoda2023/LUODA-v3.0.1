Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# window at (570,89), flutterview at (576,90). Icons around client x=430-520, y=90-130
$L = 570 + 430; $T = 90 + 80; $W = 120; $H = 60
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($L, $T, 0, 0, (New-Object System.Drawing.Size($W, $H)))
$step = 3
for ($y = 0; $y -lt $H; $y += $step) {
  $line = ''
  for ($x = 0; $x -lt $W; $x += $step) {
    $c = $bmp.GetPixel($x, $y)
    if ($c.R -gt 248 -and $c.G -gt 248 -and $c.B -gt 248) { $ch = '.' }
    elseif ($c.R -lt 80 -and $c.G -lt 80 -and $c.B -lt 80) { $ch = '#' }
    elseif ($c.G -gt 130 -and $c.R -lt 120) { $ch = 'G' }
    elseif ($c.R -gt 150 -and $c.G -gt 150 -and $c.B -gt 150) { $ch = '-' }
    elseif ($c.R -lt 150 -and $c.G -lt 150 -and $c.B -lt 150) { $ch = '+' }
    else { $ch = 'o' }
    $line += $ch
  }
  Write-Output ("c.x={0}: {1}" -f ($L + $y), $line)
}
$g.Dispose(); $bmp.Dispose()
