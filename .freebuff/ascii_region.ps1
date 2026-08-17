param([string]$File, [int]$X0, [int]$Y0, [int]$X1, [int]$Y1, [int]$Step = 2)
Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Image]::FromFile($File)
for ($y = $Y0; $y -lt $Y1; $y += $Step) {
  $line = ""
  for ($x = $X0; $x -lt $X1; $x += $Step) {
    $c = $bmp.GetPixel($x, $y)
    if ($c.G -gt 90 -and $c.R -lt 90 -and ($c.G - $c.R) -gt 40 -and ($c.G - $c.B) -gt 20) { $ch = "G" }
    elseif ($c.R -gt 245 -and $c.G -gt 245 -and $c.B -gt 245) { $ch = "." }
    elseif ($c.R -lt 60 -and $c.G -lt 60 -and $c.B -lt 60) { $ch = "#" }
    elseif ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -lt 250) { $ch = "g" }
    elseif ($c.R -gt 150 -and $c.G -gt 150 -and $c.B -gt 150) { $ch = "-" }
    elseif ($c.R -lt 120 -and $c.G -lt 120 -and $c.B -lt 120) { $ch = "+" }
    else { $ch = "o" }
    $line += $ch
  }
  Write-Output ("y={0}: {1}" -f $y, $line)
}
$bmp.Dispose()
