Add-Type -AssemblyName System.Drawing
$bmp2=[System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\after_hello.png')
for ($y=600; $y -le 875; $y+=6) {
  $line=''
  for ($x=350; $x -le 1245; $x+=8) {
    $c=$bmp2.GetPixel($x,$y)
    if ($c.R -gt 250 -and $c.G -gt 250 -and $c.B -gt 250) { $ch='.' }
    elseif ($c.R -lt 60 -and $c.G -lt 60 -and $c.B -lt 60) { $ch='#' }
    elseif ($c.G -gt 150 -and $c.R -lt 120) { $ch='G' }
    elseif ($c.R -gt 200 -and $c.G -gt 200 -and $c.B -lt 250) { $ch='g' }
    elseif ($c.R -gt 150 -and $c.G -gt 150 -and $c.B -gt 150) { $ch='-' }
    elseif ($c.R -lt 130 -and $c.G -lt 130 -and $c.B -lt 130) { $ch='+' }
    else { $ch='o' }
    $line += $ch
  }
  Write-Output ("y={0}: {1}" -f $y, $line)
}
$bmp2.Dispose()
