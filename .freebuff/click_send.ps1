param([int]$X = 882, [int]$Y = 704)
$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class SendInputClick {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
  public const uint LEFTDOWN = 0x0002;
  public const uint LEFTUP = 0x0004;
}
"@
[SendInputClick]::SetCursorPos($X, $Y) | Out-Null
Start-Sleep -Milliseconds 200
[SendInputClick]::mouse_event([SendInputClick]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero) | Out-Null
Start-Sleep -Milliseconds 80
[SendInputClick]::mouse_event([SendInputClick]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero) | Out-Null
Start-Sleep -Milliseconds 1200
Write-Host "clicked $X,$Y"
