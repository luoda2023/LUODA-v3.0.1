Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Bitmap]::FromFile("J:\codex-work\LUODA-v3.0.1\ldesk_win_1.png")
$sw = 2062
$srcRect = New-Object System.Drawing.Rectangle(0, 85, $sw, 90)
$dw = $sw * 2
$dst = New-Object System.Drawing.Rectangle(0, 0, $dw, 180)
$zoom = New-Object System.Drawing.Bitmap($dw, 180)
$g = [System.Drawing.Graphics]::FromImage($zoom)
$g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($src, $dst, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$zoom.Save("J:\codex-work\LUODA-v3.0.1\tb_full.png", [System.Drawing.Imaging.ImageFormat]::Png)
$zoom.Dispose(); $src.Dispose()
Write-Output "saved"
