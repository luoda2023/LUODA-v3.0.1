Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$L = 570; $T = 89; $W = 1220; $H = 974
$scale = 2
$bmp = New-Object System.Drawing.Bitmap(($W * $scale), ($H * $scale))
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($L, $T, 0, 0, (New-Object System.Drawing.Size($W, $H)))
$bmp.Save("J:\codex-work\LUODA-v3.0.1\.freebuff\win2x.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "ok"
