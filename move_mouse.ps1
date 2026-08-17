param([int[]]$Xs, [int[]]$Ys, [int]$Steps=6, [int]$DelayMs=80)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MoveH {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
}
"@
[void][MoveH]::SetProcessDPIAware()
for ($i = 0; $i -lt $Xs.Length; $i++) {
  [MoveH]::SetCursorPos($Xs[$i], $Ys[$i]) | Out-Null
  Start-Sleep -Milliseconds $DelayMs
}
Write-Host "moved through $($Xs.Length) points"
