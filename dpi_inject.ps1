Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class DpiInj2 {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
  public struct POINT { public int X, Y; }
}
"@
[void][DpiInj2]::SetProcessDPIAware()
[DpiInj2]::SetCursorPos(1430, 588) | Out-Null
Start-Sleep -Milliseconds 200
$p2 = New-Object DpiInj2+POINT
[DpiInj2]::GetCursorPos([ref]$p2) | Out-Null
Write-Host "Cursor at physical ($($p2.X),$($p2.Y))"
[DpiInj2]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 150
[DpiInj2]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 1200
Write-Host "click injected"
