$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\ldesk_win_1.png')
$w = $src.Width
# toolbar band: y 95..175
$crop = New-Object System.Drawing.Bitmap($w, 80)
$g = [System.Drawing.Graphics]::FromImage($crop)
$g.DrawImage($src, (New-Object System.Drawing.Rectangle(0,0,$w,80)), (New-Object System.Drawing.Rectangle(0,95,$w,80)), [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$crop.Save('J:\codex-work\LUODA-v3.0.1\tb2.png', [System.Drawing.Imaging.ImageFormat]::Png)
$crop.Dispose(); $src.Dispose()
# upscale 3x
$s2 = [System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\tb2.png')
$bmp = New-Object System.Drawing.Bitmap($s2.Width*3, $s2.Height*3)
$g2 = [System.Drawing.Graphics]::FromImage($bmp)
$g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g2.DrawImage($s2, 0, 0, $bmp.Width, $bmp.Height)
$g2.Dispose()
$bmp.Save('J:\codex-work\LUODA-v3.0.1\tb2_3x.png', [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose(); $s2.Dispose()
Write-Output 'ok'
