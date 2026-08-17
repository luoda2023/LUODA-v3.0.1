Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinCloak {
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out int pvAttribute, int cbAttribute);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
  public struct RECT { public int L, T, R, B; }
}
"@
foreach ($h in @([IntPtr]526418, [IntPtr]592070, [IntPtr]198572)) {
  $cloaked = 0
  [WinCloak]::DwmGetWindowAttribute($h, 14, [ref]$cloaked, 4) | Out-Null
  $r = New-Object WinCloak+RECT
  [WinCloak]::GetWindowRect($h, [ref]$r) | Out-Null
  $style = [WinCloak]::GetWindowLong($h, -16)
  $exstyle = [WinCloak]::GetWindowLong($h, -20)
  Write-Host ("HWND={0} visible={1} iconic={2} cloaked={3} rect={4},{5}-{6},{7} style=0x{8:x} exstyle=0x{9:x}" -f $h, [WinCloak]::IsWindowVisible($h), [WinCloak]::IsIconic($h), $cloaked, $r.L, $r.T, $r.R, $r.B, $style, $exstyle)
}
