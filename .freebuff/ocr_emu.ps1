Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Bitmap]::FromFile("J:\codex-work\LUODA-v3.0.1\.freebuff\emu_new.png")
$bmp = New-Object System.Drawing.Bitmap $img.Width, $img.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.DrawImage($img, 0, 0, $img.Width, $img.Height)
$g.Dispose()
$rect = New-Object System.Drawing.Rectangle 0,0,$bmp.Width,$bmp.Height
$data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, $bmp.PixelFormat)
$bmp.UnlockBits($data)
$bmp.Save("J:\codex-work\LUODA-v3.0.1\.freebuff\emu_ocr_in.png")
$bmp.Dispose(); $img.Dispose()
