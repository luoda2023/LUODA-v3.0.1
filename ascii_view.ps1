Add-Type -AssemblyName System.Drawing
$bmp2=[System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\full_now.png')
for ($y=600; $y -le 875; $y+=8) {
  $line=''
  for ($x=430; $x -le 1245; $x+=8) {
    $c=$bmp2.GetPixel($x,$y)
    if ($c.R -gt 245 -and $c.G -gt 245 -and $c.B -gt 245) { $ch='.' }  # white
    elseif ($c.R -lt 60 -and $c.G -lt 60 -and $c.B -lt 60) { $ch='#' } # black
    elseif ($c.G -gt 150 -and $c.R -lt 120) { $ch='G' } # green
    elseif ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -lt 250) { $ch='g' } # light green
    elseif ($c.R -gt 150 -and $c.G -gt 150 -and $c.B -gt 150) { $ch='-' } # light gray
    elseif ($c.R -lt 120 -and $c.G -lt 120 -and $c.B -lt 120) { $ch='+' } # dark
    else { $ch='o' }
    $line += $ch
  }
  Write-Output ("y={0}: {1}" -f $y, $line)
}
$bmp2.Dispose()
