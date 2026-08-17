Add-Type -AssemblyName System.Drawing
$bmp2=[System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\after_hello.png')
# check send button area color at several points (window-local physical)
foreach ($pt in @(@(1080,830),@(1100,830),@(1120,830),@(1130,830),@(1140,830),@(1080,840),@(1130,840))) {
  $c=$bmp2.GetPixel($pt[0],$pt[1])
  Write-Output ("({0},{1}) rgb=({2},{3},{4})" -f $pt[0],$pt[1],$c.R,$c.G,$c.B)
}
# also check hint area for HELLO text
$c1=$bmp2.GetPixel(460,700); Write-Output ("hint area (460,700): ({0},{1},{2})" -f $c1.R,$c1.G,$c1.B)
$bmp2.Dispose()
