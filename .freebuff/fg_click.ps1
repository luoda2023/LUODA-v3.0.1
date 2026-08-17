param([int]$X = 0, [int]$Y = 0, [int]$Hwnd = 0)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class FgClick {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr p);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
}
'@
$h = [IntPtr]$Hwnd
[FgClick]::ShowWindow($h, 9) | Out-Null
[FgClick]::SetForegroundWindow($h) | Out-Null
[FgClick]::BringWindowToTop($h) | Out-Null
Start-Sleep -Milliseconds 300
[FgClick]::SetCursorPos($X, $Y) | Out-Null
Start-Sleep -Milliseconds 150
[FgClick]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
[FgClick]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Write-Output "fg+click $X,$Y hwnd=$Hwnd"
