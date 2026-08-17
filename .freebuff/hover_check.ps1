param([int]$X = 1025, [int]$Y = 205)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Hover1 {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
}
"@
[Hover1]::SetCursorPos($X, $Y) | Out-Null
Start-Sleep -Milliseconds 1500
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$L = 560; $T = 60; $W = 1240; $H = 320
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($L, $T, 0, 0, (New-Object System.Drawing.Size($W, $H)))
$bmp.Save("J:\codex-work\LUODA-v3.0.1\.freebuff\hover.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "captured after hover at $X,$Y"
