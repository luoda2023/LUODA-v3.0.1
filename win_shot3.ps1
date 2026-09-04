Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Cap {
  [DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetWindowDC(IntPtr h);
  [DllImport("gdi32.dll")] public static extern bool BitBlt(IntPtr hdcDest,int x,int y,int w,int h,IntPtr hdcSrc,int x1,int y1,int op);
  [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h,IntPtr dc);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr h);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleBitmap(IntPtr h,int w,int hh);
  [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr h,IntPtr o);
  [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr o);
  [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr h);
}
"@
Add-Type -AssemblyName System.Drawing
$w=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
$h=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
$desk=[Cap]::GetDesktopWindow()
$dc=[Cap]::GetWindowDC($desk)
$cdc=[Cap]::CreateCompatibleDC($dc)
$bmp=[Cap]::CreateCompatibleBitmap($dc,$w,$h)
$old=[Cap]::SelectObject($cdc,$bmp)
[Cap]::BitBlt($cdc,0,0,$w,$h,$dc,0,0,0x00CC0020)|Out-Null
$img=[System.Drawing.Image]::FromHbitmap($bmp)
$img.Save("J:\codex-work\LUODA-v3.0.1\_win_full.png",[System.Drawing.Imaging.ImageFormat]::Png)
[Cap]::SelectObject($cdc,$old)|Out-Null
[Cap]::DeleteObject($bmp)|Out-Null
[Cap]::DeleteDC($cdc)|Out-Null
[Cap]::ReleaseDC($desk,$dc)|Out-Null
$img.Dispose()
Write-Output "saved $w x $h"
