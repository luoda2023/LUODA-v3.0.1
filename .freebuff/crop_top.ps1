Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot "pw_now.png"))
$crop = New-Object System.Drawing.Bitmap($src.Width, 260)
$g = [System.Drawing.Graphics]::FromImage($crop)
$g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $src.Width, 260)), (New-Object System.Drawing.Rectangle(0, 0, $src.Width, 260)), [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$crop.Save((Join-Path $PSScriptRoot "pw_top.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$crop.Dispose(); $src.Dispose()
Write-Host "saved pw_top.png"
