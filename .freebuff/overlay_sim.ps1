$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Sim {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
}
'@
# 拖拽从 (600,400) 到 (1000,700)
[Sim]::SetCursorPos(600, 400) | Out-Null
Start-Sleep -Milliseconds 300
[Sim]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)  # LEFTDOWN
Start-Sleep -Milliseconds 100
$steps = 12
for ($i = 1; $i -le $steps; $i++) {
  $x = 600 + [int]((1000 - 600) * $i / $steps)
  $y = 400 + [int]((700 - 400) * $i / $steps)
  [Sim]::SetCursorPos($x, $y) | Out-Null
  Start-Sleep -Milliseconds 40
}
Start-Sleep -Milliseconds 100
[Sim]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)  # LEFTUP
Write-Output "drag done"
