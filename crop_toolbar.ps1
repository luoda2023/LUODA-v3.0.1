$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\ldesk_win_1.png')
$w = $src.Width; $h = $src.Height
Write-Output "full ${w}x${h}"
# toolbar area near top (title ~28-70, toolbar ~100-150). Capture y=90..170 full width
$crop = New-Object System.Drawing.Bitmap($w, 90)
$g = [System.Drawing.Graphics]::FromImage($crop)
$g.DrawImage($src, (New-Object System.Drawing.Rectangle(0,0,$w,90)), (New-Object System.Drawing.Rectangle(0,85,$w,90)), [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$crop.Save('J:\codex-work\LUODA-v3.0.1\toolbar_strip.png', [System.Drawing.Imaging.ImageFormat]::Png)
$crop.Dispose(); $src.Dispose()
Write-Output 'saved toolbar_strip.png'
