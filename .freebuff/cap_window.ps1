param([int]$Hwnd = 0, [string]$Out = "C:\Users\Administrator\AppData\Local\Temp\cap.png", [int]$Flag = 2)
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class PWC4 {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  public struct RECT { public int L, T, R, B; }
}
'@
$h = [IntPtr]$Hwnd
Write-Output "visible=$([PWC4]::IsWindowVisible($h)) iconic=$([PWC4]::IsIconic($h)) zoomed=$([PWC4]::IsZoomed($h))"
$r = New-Object PWC4+RECT
[PWC4]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.R - $r.L; $hh = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap($w, $hh)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [PWC4]::PrintWindow($h, $hdc, $Flag)
$g.ReleaseHdc($hdc)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "ok=$ok flag=$Flag rect=$($r.L),$($r.T),$($r.R),$($r.B) size=${w}x${hh}"
