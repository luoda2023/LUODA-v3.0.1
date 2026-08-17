Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Bitmap]::FromFile("J:\codex-work\LUODA-v3.0.1\remote_fresh.png")
# The dialog appeared around y=880 in earlier capture. Search a wider band y=800..1000, x=900..1700
$srcRect = New-Object System.Drawing.Rectangle(900, 800, 800, 220)
$dw = 800 * 3
$zoom = New-Object System.Drawing.Bitmap($dw, 660)
$g = [System.Drawing.Graphics]::FromImage($zoom)
$g.InterpolationMode = 'HighQualityBicubic'
$dst = New-Object System.Drawing.Rectangle(0, 0, $dw, 660)
$g.DrawImage($src, $dst, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$zoom.Save("J:\codex-work\LUODA-v3.0.1\dlg3.png", [System.Drawing.Imaging.ImageFormat]::Png)
$zoom.Dispose(); $src.Dispose()
Write-Output "saved"
