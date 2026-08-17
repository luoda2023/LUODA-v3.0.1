Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$L = 1030; $T = 89; $W = 760; $H = 140
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($L, $T, 0, 0, (New-Object System.Drawing.Size($W, $H)))
$bmp.Save("J:\codex-work\LUODA-v3.0.1\.freebuff\right_head.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "ok"
