param([string]$File, [int]$CX, [int]$CY, [int]$R = 25)
Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Image]::FromFile($File)
Write-Host "grid around ($CX,$CY) from ${File}:"
for ($y = $CY - $R; $y -le $CY + $R; $y += 2) {
  $line = ""
  for ($x = $CX - $R; $x -le $CX + $R; $x += 2) {
    if ($x -lt 0 -or $y -lt 0 -or $x -ge $bmp.Width -or $y -ge $bmp.Height) { $line += "?"; continue }
    $c = $bmp.GetPixel($x, $y)
    if ($c.G -gt 100 -and $c.R -lt 100 -and ($c.G - $c.R) -gt 40) { $ch = "G" }
    elseif ($c.R -gt 240 -and $c.G -gt 240 -and $c.B -gt 240) { $ch = "." }
    elseif ($c.R -lt 100 -and $c.G -lt 100 -and $c.B -lt 100) { $ch = "#" }
    elseif ($c.R -gt 150 -and $c.G -gt 150 -and $c.B -gt 150) { $ch = "-" }
    else { $ch = "o" }
    $line += $ch
  }
  Write-Output ("  y={0}: {1}" -f $y, $line)
}
$bmp.Dispose()
