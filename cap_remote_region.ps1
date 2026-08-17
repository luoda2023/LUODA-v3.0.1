$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$L = 1150; $T = 250; $W = 880; $H = 640
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($L, $T, 0, 0, (New-Object System.Drawing.Size($W, $H)))
$bmp.Save("J:\codex-work\LUODA-v3.0.1\agent_memory\remote_region.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
$c = Get-Content ocr_mstsc.ps1 -Raw; $c = $c.Replace('mstsc2x.png','agent_memory\remote_region.png')
Set-Content ocr_remote_region.ps1 -Value $c -Encoding UTF8
Write-Host "captured"
