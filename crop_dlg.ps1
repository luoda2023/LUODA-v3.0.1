Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Bitmap]::FromFile("J:\codex-work\LUODA-v3.0.1\remote_fresh.png")
$sw = 2062; $sh = 1246
# center region around dialog (y 850-950)
$srcRect = New-Object System.Drawing.Rectangle(1000, 840, 1062, 130)
$dw = 1062 * 2
$zoom = New-Object System.Drawing.Bitmap($dw, 260)
$g = [System.Drawing.Graphics]::FromImage($zoom)
$g.InterpolationMode = 'HighQualityBicubic'
$dst = New-Object System.Drawing.Rectangle(0, 0, $dw, 260)
$g.DrawImage($src, $dst, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$zoom.Save("J:\codex-work\LUODA-v3.0.1\dlg.png", [System.Drawing.Imaging.ImageFormat]::Png)
$zoom.Dispose(); $src.Dispose()
Write-Output "saved"
