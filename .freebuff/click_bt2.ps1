$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FC2 {
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
  [FC2]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
  if ([int]$p -eq 20180 -and [FC2]::IsWindowVisible($h)) { $script:hWnd = $h; return $false }
  return $true
}
[FC2]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
[FC2]::ShowWindow($hWnd, 9) | Out-Null
[FC2]::SetForegroundWindow($hWnd) | Out-Null
Start-Sleep -Milliseconds 300
[FC2]::BringWindowToTop($hWnd) | Out-Null
[FC2]::SetForegroundWindow($hWnd) | Out-Null
Start-Sleep -Milliseconds 700
[FC2]::SetCursorPos(1063, 194) | Out-Null
Start-Sleep -Milliseconds 250
[FC2]::mouse_event([FC2]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero) | Out-Null
Start-Sleep -Milliseconds 90
[FC2]::mouse_event([FC2]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero) | Out-Null
Start-Sleep -Milliseconds 2000
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap(1220, 974)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(570, 89, 0, 0, (New-Object System.Drawing.Size(1220, 974)))
$bmp.Save("J:\codex-work\LUODA-v3.0.1\.freebuff\bt2.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "done"
