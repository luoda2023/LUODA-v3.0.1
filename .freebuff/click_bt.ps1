$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FocusClick {
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
  [FocusClick]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
  if ([int]$p -eq 20180 -and [FocusClick]::IsWindowVisible($h)) { $script:hWnd = $h; return $false }
  return $true
}
[FocusClick]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
if ($hWnd -eq [IntPtr]::Zero) { Write-Host "no window"; exit 1 }
[FocusClick]::ShowWindow($hWnd, 9) | Out-Null
[FocusClick]::SetForegroundWindow($hWnd) | Out-Null
Start-Sleep -Milliseconds 300
[FocusClick]::BringWindowToTop($hWnd) | Out-Null
[FocusClick]::SetForegroundWindow($hWnd) | Out-Null
Start-Sleep -Milliseconds 500
# click bluetooth icon
[FocusClick]::SetCursorPos(1042, 197) | Out-Null
Start-Sleep -Milliseconds 150
[FocusClick]::mouse_event([FocusClick]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero) | Out-Null
[FocusClick]::mouse_event([FocusClick]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero) | Out-Null
Start-Sleep -Milliseconds 1800
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, $b.Size)
$bmp.Save("J:\codex-work\LUODA-v3.0.1\.freebuff\bt_page.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "clicked and captured"
