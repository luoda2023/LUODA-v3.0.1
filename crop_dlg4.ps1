Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Bitmap]::FromFile("J:\codex-work\LUODA-v3.0.1\remote_fresh.png")
# dialog center area ~ y 850-980, x 950-1700
$srcRect = New-Object System.Drawing.Rectangle(950, 830, 760, 170)
$dw = 760 * 3
$zoom = New-Object System.Drawing.Bitmap($dw, 510)
$g = [System.Drawing.Graphics]::FromImage($zoom)
$g.InterpolationMode = 'HighQualityBicubic'
$dst = New-Object System.Drawing.Rectangle(0, 0, $dw, 510)
$g.DrawImage($src, $dst, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$zoom.Save("J:\codex-work\LUODA-v3.0.1\dlg4.png", [System.Drawing.Imaging.ImageFormat]::Png)
$zoom.Dispose(); $src.Dispose()
Write-Output "saved"
