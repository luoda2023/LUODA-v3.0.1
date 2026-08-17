param([string]$File, [int]$X0, [int]$Y0, [int]$X1, [int]$Y1)
Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Image]::FromFile($File)
for ($y = $Y0; $y -le $Y1; $y += 2) {
  $line = ""
  for ($x = $X0; $x -le $X1; $x += 2) {
    $c = $bmp.GetPixel($x, $y)
    $line += ("{0},{1},{2} " -f $c.R, $c.G, $c.B)
  }
  Write-Output ("y={0}: {1}" -f $y, $line)
}
$bmp.Dispose()
