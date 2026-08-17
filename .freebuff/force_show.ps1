param([int]$Hwnd = 0)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class WinShow {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int cx, int cy, bool r);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
}
'@
$h = [IntPtr]$Hwnd
[WinShow]::ShowWindow($h, 5) | Out-Null   # SW_SHOW
Start-Sleep -Milliseconds 150
[WinShow]::ShowWindow($h, 9) | Out-Null   # SW_RESTORE
Start-Sleep -Milliseconds 300
[WinShow]::MoveWindow($h, 150, 60, 1220, 974, $true) | Out-Null
Start-Sleep -Milliseconds 300
"iconic=$([WinShow]::IsIconic($h)) shown=$h"
