Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Cap4 {
  [DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetWindowDC(IntPtr h);
  [DllImport("gdi32.dll")] public static extern bool BitBlt(IntPtr hdcDest,int x,int y,int w,int h,IntPtr hdcSrc,int x1,int y1,int op);
  [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h,IntPtr dc);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr h);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleBitmap(IntPtr h,int w,int hh);
  [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr h,IntPtr o);
  [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr o);
  [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
"@
$h=[IntPtr]4851870
[Cap4]::SetForegroundWindow($h)|Out-Null
Start-Sleep -Milliseconds 800
$w=2048; $hh=1280
$desk=[Cap4]::GetDesktopWindow()
$dc=[Cap4]::GetWindowDC($desk)
$cdc=[Cap4]::CreateCompatibleDC($dc)
$bmp=[Cap4]::CreateCompatibleBitmap($dc,$w,$hh)
$old=[Cap4]::SelectObject($cdc,$bmp)
[Cap4]::BitBlt($cdc,0,0,$w,$hh,$dc,0,0,0x00CC0020)|Out-Null
$img=[System.Drawing.Image]::FromHbitmap($bmp)
$img.Save("J:\codex-work\LUODA-v3.0.1\_win2.png",[System.Drawing.Imaging.ImageFormat]::Png)
[Cap4]::SelectObject($cdc,$old)|Out-Null
[Cap4]::DeleteObject($bmp)|Out-Null
[Cap4]::DeleteDC($cdc)|Out-Null
[Cap4]::ReleaseDC($desk,$dc)|Out-Null
$img.Dispose()
Write-Output "saved $w x $hh"
