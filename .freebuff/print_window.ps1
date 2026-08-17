param([IntPtr]$Hwnd = [IntPtr]3935734, [string]$Out = "C:\Users\Administrator\AppData\Local\Temp\pw_ldesk.png")
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class PWC {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  public struct RECT { public int L, T, R, B; }
}
'@
Add-Type -AssemblyName System.Drawing
$r = New-Object PWC+RECT
[PWC]::GetWindowRect($Hwnd, [ref]$r) | Out-Null
$w = $r.R - $r.L; $h = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [PWC]::PrintWindow($Hwnd, $hdc, 2)
$g.ReleaseHdc($hdc)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("PrintWindow ok=" + $ok + " size=" + $w + "x" + $h)
