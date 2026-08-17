Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Bitmap]::FromFile("J:\codex-work\LUODA-v3.0.1\main_win_print.png")
# crop header+toolbar band y=55..150 then 3x zoom
$crop = New-Object System.Drawing.Bitmap(1000, 100)
$g = [System.Drawing.Graphics]::FromImage($crop)
$g.DrawImage($src, (New-Object System.Drawing.Rectangle(0,0,1000,100)), (New-Object System.Drawing.Rectangle(0,55,1000,100)), [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$zoom = New-Object System.Drawing.Bitmap(1500, 150)
$g2 = [System.Drawing.Graphics]::FromImage($zoom)
$g2.InterpolationMode = 'NearestNeighbor'
$g2.DrawImage($crop, 0, 0, 1500, 150)
$g2.Dispose()
$zoom.Save("J:\codex-work\LUODA-v3.0.1\main_header_zoom.png", [System.Drawing.Imaging.ImageFormat]::Png)
$crop.Dispose(); $zoom.Dispose()
Write-Output "saved"
