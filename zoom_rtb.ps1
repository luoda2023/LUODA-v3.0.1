Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Bitmap]::FromFile("J:\codex-work\LUODA-v3.0.1\remote_fresh.png")
$zoom = New-Object System.Drawing.Bitmap(1760, 400)
$g = [System.Drawing.Graphics]::FromImage($zoom)
$g.InterpolationMode = 'NearestNeighbor'
$dst = New-Object System.Drawing.Rectangle(0, 0, 1760, 400)
$srcRect = New-Object System.Drawing.Rectangle(0, 55, 880, 200)
$g.DrawImage($src, $dst, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$zoom.Save("J:\codex-work\LUODA-v3.0.1\remote_toolbar_zoom.png", [System.Drawing.Imaging.ImageFormat]::Png)
$zoom.Dispose(); $src.Dispose()
Write-Output "saved"
