Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap(880, 640)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(179, 179, 0, 0, (New-Object System.Drawing.Size(880, 640)))
$bmp.Save("J:\codex-work\LUODA-v3.0.1\ldesk_front.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "captured"
