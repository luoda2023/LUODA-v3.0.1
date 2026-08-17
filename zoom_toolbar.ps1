$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
# upscale 2x for OCR
$src = [System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\toolbar_strip.png')
$w = $src.Width * 2; $h = $src.Height * 2
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($src, 0, 0, $w, $h)
$g.Dispose()
$bmp.Save('J:\codex-work\LUODA-v3.0.1\toolbar_strip_2x.png', [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose(); $src.Dispose()
Write-Output 'ok'
