param([string]$File, [string]$Out, [int]$Y0, [int]$Y1)
Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Image]::FromFile($File)
$h = $Y1 - $Y0
$crop = New-Object System.Drawing.Bitmap($src.Width, $h)
$g = [System.Drawing.Graphics]::FromImage($crop)
$g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $src.Width, $h)), (New-Object System.Drawing.Rectangle(0, $Y0, $src.Width, $h)), [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$crop.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$crop.Dispose(); $src.Dispose()
Write-Host "saved $Out"
