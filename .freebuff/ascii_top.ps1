param([string]$File, [int]$Rows = 260, [int]$Step = 4)
Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Image]::FromFile($File)
$w = $bmp.Width; $h = $bmp.Height
for ($y = 0; $y -lt [Math]::Min($Rows, $h); $y += $Step) {
  $line = ""
  for ($x = 0; $x -lt $w; $x += $Step) {
    $c = $bmp.GetPixel($x, $y)
    if ($c.R -gt 245 -and $c.G -gt 245 -and $c.B -gt 245) { $ch = "." }
    elseif ($c.R -lt 60 -and $c.G -lt 60 -and $c.B -lt 60) { $ch = "#" }
    elseif ($c.G -gt 150 -and $c.R -lt 80 -and $c.B -lt 130) { $ch = "G" }
    elseif ($c.R -gt 200 -and $c.G -gt 130 -and $c.B -lt 90) { $ch = "O" }
    elseif ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -lt 250) { $ch = "g" }
    elseif ($c.R -gt 150 -and $c.G -gt 150 -and $c.B -gt 150) { $ch = "-" }
    elseif ($c.R -lt 120 -and $c.G -lt 120 -and $c.B -lt 120) { $ch = "+" }
    else { $ch = "o" }
    $line += $ch
  }
  Write-Output ("y={0}: {1}" -f $y, $line)
}
$bmp.Dispose()
