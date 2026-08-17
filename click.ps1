param(
  [int]$X, [int]$Y, [string]$Click = "left", [int]$Times = 1
)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MouseOps {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
  public const uint LEFTDOWN = 0x0002;
  public const uint LEFTUP = 0x0004;
  public const uint RIGHTDOWN = 0x0008;
  public const uint RIGHTUP = 0x0010;
}
"@
[MouseOps]::SetCursorPos($X, $Y) | Out-Null
Start-Sleep -Milliseconds 120
for ($i = 0; $i -lt $Times; $i++) {
  if ($Click -eq "right") {
    [MouseOps]::mouse_event([MouseOps]::RIGHTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    [MouseOps]::mouse_event([MouseOps]::RIGHTUP, 0, 0, 0, [UIntPtr]::Zero)
  } else {
    [MouseOps]::mouse_event([MouseOps]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    [MouseOps]::mouse_event([MouseOps]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
  }
  if ($i -lt ($Times - 1)) { Start-Sleep -Milliseconds 150 }
}
Write-Host "clicked $Click at $X,$Y x$Times"
