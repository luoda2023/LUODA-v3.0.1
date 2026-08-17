param([string]$Out = "C:\Users\Administrator\AppData\Local\Temp\bit.png")
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class ScrBlt {
  [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
  [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr hdc);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int w, int h);
  [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr hdc, IntPtr o);
  [DllImport("gdi32.dll")] public static extern bool BitBlt(IntPtr dst, int x, int y, int w, int h, IntPtr src, int sx, int sy, uint rop);
  [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr dc);
  [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr o);
}
'@
$hdc = [ScrBlt]::GetDC([IntPtr]::Zero)
$mem = [ScrBlt]::CreateCompatibleDC($hdc)
$bmp = [ScrBlt]::CreateCompatibleBitmap($hdc, 2048, 1280)
$old = [ScrBlt]::SelectObject($mem, $bmp)
[ScrBlt]::BitBlt($mem, 0, 0, 2048, 1280, $hdc, 0, 0, 0x00CC0020) | Out-Null
[ScrBlt]::SelectObject($mem, $old)
[ScrBlt]::DeleteDC($mem)
[ScrBlt]::ReleaseDC([IntPtr]::Zero, $hdc)
$img = [System.Drawing.Image]::FromHbitmap($bmp)
$img.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$img.Dispose()
[ScrBlt]::DeleteObject($bmp)
Write-Output "bitblt saved"
