param([int]$X, [int]$Y, [int]$W, [int]$H, [string]$Out)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Cap {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
  [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr hdc);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int w, int h);
  [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);
  [DllImport("gdi32.dll")] public static extern bool BitBlt(IntPtr hdc, int x, int y, int w, int h, IntPtr src, int sx, int sy, uint rop);
  [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr obj);
  [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr dc);
}
"@
[void][Cap]::SetProcessDPIAware()
$dc = [Cap]::GetDC([IntPtr]::Zero)
$cdc = [Cap]::CreateCompatibleDC($dc)
$bmp = [Cap]::CreateCompatibleBitmap($dc, $W, $H)
[Cap]::SelectObject($cdc, $bmp) | Out-Null
[Cap]::BitBlt($cdc, 0, 0, $W, $H, $dc, $X, $Y, 0x00CC0020) | Out-Null
$b = [System.Drawing.Image]::FromHbitmap($bmp)
$b.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
[Cap]::DeleteObject($bmp); [Cap]::DeleteDC($cdc); [Cap]::ReleaseDC([IntPtr]::Zero, $dc)
Write-Host "saved $Out ($W x $H at $X,$Y)"
