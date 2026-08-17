Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# List monitors
foreach ($m in [System.Windows.Forms.Screen]::AllScreens) {
  Write-Host ("Screen: " + $m.DeviceName + " Bounds=" + $m.Bounds + " Primary=" + $m.Primary)
}
$bmpFull = New-Object System.Drawing.Bitmap(2048, 1280)
$g1 = [System.Drawing.Graphics]::FromImage($bmpFull)
$g1.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size(2048, 1280)))
$bmpFull.Save("J:\codex-work\LUODA-v3.0.1\.freebuff\diag_full.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmpReg = New-Object System.Drawing.Bitmap(1220, 974)
$g2 = [System.Drawing.Graphics]::FromImage($bmpReg)
$g2.CopyFromScreen(570, 89, 0, 0, (New-Object System.Drawing.Size(1220, 974)))
$bmpReg.Save("J:\codex-work\LUODA-v3.0.1\.freebuff\diag_reg.png", [System.Drawing.Imaging.ImageFormat]::Png)
# Compare same absolute point (700,300) -> full(700,300) vs reg(130,211)
$cFull = $bmpFull.GetPixel(700, 300)
$cReg = $bmpReg.GetPixel(130, 211)
Write-Host ("full(700,300)={0},{1},{2}  reg(130,211)={3},{4},{5}" -f $cFull.R, $cFull.G, $cFull.B, $cReg.R, $cReg.G, $cReg.B)
# sample a grid of the region to see if it's LDesk UI (light background) or wallpaper
$light = 0; $dark = 0
for ($x = 0; $x -lt 1220; $x += 40) {
  for ($y = 0; $y -lt 974; $y += 40) {
    $c = $bmpReg.GetPixel($x, $y)
    if (($c.R + $c.G + $c.B) -gt 650) { $light++ } else { $dark++ }
  }
}
Write-Host ("region: light=$light dark=$dark")
$light2 = 0; $dark2 = 0
for ($x = 570; $x -lt 1790; $x += 40) {
  for ($y = 89; $y -lt 1063; $y += 40) {
    $c = $bmpFull.GetPixel($x, $y)
    if (($c.R + $c.G + $c.B) -gt 650) { $light2++ } else { $dark2++ }
  }
}
Write-Host ("full-region: light=$light2 dark=$dark2")
$g1.Dispose(); $g2.Dispose(); $bmpFull.Dispose(); $bmpReg.Dispose()
