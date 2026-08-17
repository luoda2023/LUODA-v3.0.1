param([int]$X = 0, [int]$Y = 0, [int]$Dbl = 0)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class ClickScr {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
}
'@
[ClickScr]::SetCursorPos($X, $Y) | Out-Null
Start-Sleep -Milliseconds 120
[ClickScr]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)  # LEFTDOWN
Start-Sleep -Milliseconds 60
[ClickScr]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)  # LEFTUP
if ($Dbl -eq 1) {
  Start-Sleep -Milliseconds 90
  [ClickScr]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 60
  [ClickScr]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}
Write-Output "clicked $X,$Y"
