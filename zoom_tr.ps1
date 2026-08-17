Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Bitmap]::FromFile("J:\codex-work\LUODA-v3.0.1\main_win_print.png")
$zoom = New-Object System.Drawing.Bitmap(1200, 150)
$g = [System.Drawing.Graphics]::FromImage($zoom)
$g.InterpolationMode = 'NearestNeighbor'
$dst = New-Object System.Drawing.Rectangle(0, 0, 1200, 150)
$srcRect = New-Object System.Drawing.Rectangle(400, 50, 600, 75)
$g.DrawImage($src, $dst, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$zoom.Save("J:\codex-work\LUODA-v3.0.1\main_topright_zoom.png", [System.Drawing.Imaging.ImageFormat]::Png)
$zoom.Dispose(); $src.Dispose()
Write-Output "saved"
