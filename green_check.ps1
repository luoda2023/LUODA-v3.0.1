Add-Type -AssemblyName System.Drawing
foreach ($f in @('main_win.png','main_after_type.png','main_after_paste.png','focus_check.png')) {
  $bmp2=[System.Drawing.Image]::FromFile("J:\codex-work\LUODA-v3.0.1\$f")
  $green=0
  for ($y=795; $y -le 810; $y+=1) { for ($x=440; $x -le 1140; $x+=2) {
    $c=$bmp2.GetPixel($x,$y)
    if ([Math]::Abs($c.R-7) -le 20 -and [Math]::Abs($c.G-193) -le 20 -and [Math]::Abs($c.B-96) -le 20) { $green++ }
  }}
  Write-Output "$f : green pixels near y=795..810: $green"
  $bmp2.Dispose()
}
