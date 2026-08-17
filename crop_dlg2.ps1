Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Bitmap]::FromFile("J:\codex-work\LUODA-v3.0.1\remote_fresh.png")
# dialog at y~850-950, x~1000-1650
$srcRect = New-Object System.Drawing.Rectangle(950, 830, 800, 160)
$dw = 800 * 3
$zoom = New-Object System.Drawing.Bitmap($dw, 480)
$g = [System.Drawing.Graphics]::FromImage($zoom)
$g.InterpolationMode = 'HighQualityBicubic'
$dst = New-Object System.Drawing.Rectangle(0, 0, $dw, 480)
$g.DrawImage($src, $dst, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$zoom.Save("J:\codex-work\LUODA-v3.0.1\dlg_big.png", [System.Drawing.Imaging.ImageFormat]::Png)
$zoom.Dispose(); $src.Dispose()
Write-Output "saved"
