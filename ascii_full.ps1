Add-Type -AssemblyName System.Drawing
$bmp2=[System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\full_now.png')
for ($y=90; $y -le 875; $y+=12) {
  $line=''
  for ($x=0; $x -le 1245; $x+=10) {
    $c=$bmp2.GetPixel($x,$y)
    if ($c.R -gt 245 -and $c.G -gt 245 -and $c.B -gt 245) { $ch='.' }
    elseif ($c.R -lt 60 -and $c.G -lt 60 -and $c.B -lt 60) { $ch='#' }
    elseif ($c.G -gt 150 -and $c.R -lt 120) { $ch='G' }
    elseif ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -lt 250) { $ch='g' }
    elseif ($c.R -gt 150 -and $c.G -gt 150 -and $c.B -gt 150) { $ch='-' }
    elseif ($c.R -lt 120 -and $c.G -lt 120 -and $c.B -lt 120) { $ch='+' }
    else { $ch='o' }
    $line += $ch
  }
  Write-Output ("y={0}: {1}" -f $y, $line)
}
$bmp2.Dispose()
