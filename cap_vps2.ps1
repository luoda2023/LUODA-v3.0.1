$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$L = 50; $T = 50; $W = 1050; $H = 650
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($L, $T, 0, 0, (New-Object System.Drawing.Size($W, $H)))
$bmp.Save("J:\codex-work\LUODA-v3.0.1\agent_memory\vps_now2.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
$c = Get-Content ocr_mstsc.ps1 -Raw; $c = $c.Replace('mstsc2x.png','agent_memory\vps_now2.png')
Set-Content ocr_vps2.ps1 -Value $c -Encoding UTF8
Write-Host "captured"
