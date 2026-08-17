$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$L = 442; $T = 236; $W = 1040; $H = 592
$bmp = New-Object System.Drawing.Bitmap(($W * 2), ($H * 2))
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($L, $T, 0, 0, (New-Object System.Drawing.Size($W, $H)))
$bmp.Save("J:\codex-work\LUODA-v3.0.1\agent_memory\remote2x.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "captured"
