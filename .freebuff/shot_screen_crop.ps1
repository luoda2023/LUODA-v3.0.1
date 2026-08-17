Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class ScrBlt2 {
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
$hdc = [ScrBlt2]::GetDC([IntPtr]::Zero)
$mem = [ScrBlt2]::CreateCompatibleDC($hdc)
$bmp = [ScrBlt2]::CreateCompatibleBitmap($hdc, 2560, 1440)
$old = [ScrBlt2]::SelectObject($mem, $bmp)
[ScrBlt2]::BitBlt($mem, 0, 0, 2560, 1440, $hdc, 0, 0, 0x00CC0020) | Out-Null
[ScrBlt2]::SelectObject($mem, $old)
[ScrBlt2]::DeleteDC($mem)
[ScrBlt2]::ReleaseDC([IntPtr]::Zero, $hdc)
$img = [System.Drawing.Image]::FromHbitmap($bmp)
$img.Save("J:\codex-work\LUODA-v3.0.1\.freebuff\screen_full_now.png", [System.Drawing.Imaging.ImageFormat]::Png)
$img.Dispose()
[ScrBlt2]::DeleteObject($bmp)
# 裁剪 luoda 窗口区域
$src = [System.Drawing.Image]::FromFile("J:\codex-work\LUODA-v3.0.1\.freebuff\screen_full_now.png")
$crop = New-Object System.Drawing.Bitmap(1220, 974)
$g = [System.Drawing.Graphics]::FromImage($crop)
$g.DrawImage($src, (New-Object System.Drawing.Rectangle(0,0,1220,974)), (New-Object System.Drawing.Rectangle(435,142,1220,974)), [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$crop.Save("J:\codex-work\LUODA-v3.0.1\.freebuff\pc_main_crop.png", [System.Drawing.Imaging.ImageFormat]::Png)
$crop.Dispose()
$src.Dispose()
Write-Output "saved"
