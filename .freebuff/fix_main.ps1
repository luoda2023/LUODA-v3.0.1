param([int]$Hwnd = 0)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class WinFix2 {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int cx, int cy, bool r);
}
'@
$h = [IntPtr]$Hwnd
[WinFix2]::ShowWindow($h, 9) | Out-Null  # SW_RESTORE
Start-Sleep -Milliseconds 200
[WinFix2]::MoveWindow($h, 150, 60, 1220, 974, $true) | Out-Null
Start-Sleep -Milliseconds 200
[WinFix2]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0040) | Out-Null  # TOPMOST show
"fixed $h"
