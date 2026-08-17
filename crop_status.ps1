Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Bitmap]::FromFile("J:\codex-work\LUODA-v3.0.1\ldesk_win_1.png")
# top status bar y=15..55, x=1150..2062
$srcRect = New-Object System.Drawing.Rectangle(1150, 15, 912, 45)
$dw = 912 * 2
$zoom = New-Object System.Drawing.Bitmap($dw, 90)
$g = [System.Drawing.Graphics]::FromImage($zoom)
$g.InterpolationMode = 'HighQualityBicubic'
$dst = New-Object System.Drawing.Rectangle(0, 0, $dw, 90)
$g.DrawImage($src, $dst, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$zoom.Save("J:\codex-work\LUODA-v3.0.1\status_top.png", [System.Drawing.Imaging.ImageFormat]::Png)
$zoom.Dispose(); $src.Dispose()
Write-Output "saved"
