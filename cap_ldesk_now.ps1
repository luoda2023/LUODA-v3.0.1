Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap(1000, 700)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(994, 67, 0, 0, (New-Object System.Drawing.Size(1000, 700)))
$bmp.Save("J:\codex-work\LUODA-v3.0.1\ldesk_now.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "captured"
