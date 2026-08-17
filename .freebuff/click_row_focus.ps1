param([int]$X = 882, [int]$Y = 909)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FC3 {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
  public const uint LEFTDOWN = 0x0002;
  public const uint LEFTUP = 0x0004;
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
}
"@
$hWnd = [IntPtr]::Zero
$cb = {
  param($h, $lp)
  $p = 0
  [FC3]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
  if ([int]$p -eq 20180 -and [FC3]::IsWindowVisible($h)) { $script:hWnd = $h; return $false }
  return $true
}
[FC3]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
[FC3]::ShowWindow($hWnd, 9) | Out-Null
[FC3]::SetForegroundWindow($hWnd) | Out-Null
Start-Sleep -Milliseconds 250
[FC3]::BringWindowToTop($hWnd) | Out-Null
[FC3]::SetForegroundWindow($hWnd) | Out-Null
Start-Sleep -Milliseconds 600
[FC3]::SetCursorPos($X, $Y) | Out-Null
Start-Sleep -Milliseconds 200
[FC3]::mouse_event([FC3]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero) | Out-Null
Start-Sleep -Milliseconds 80
[FC3]::mouse_event([FC3]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero) | Out-Null
Start-Sleep -Milliseconds 1500
Write-Host "focused and clicked $X,$Y"
