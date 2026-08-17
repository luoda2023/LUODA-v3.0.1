# Force-activate the LUODA main window so simulated clicks reach it.
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class FgWin {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetFocus(IntPtr h);
}
'@
$p = Get-Process luoda -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Write-Output "NO_PROCESS"; exit 1 }
$hwnd = $p.MainWindowHandle
# Restore if minimized
[FgWin]::ShowWindow($hwnd, 9) | Out-Null   # SW_RESTORE
Start-Sleep -Milliseconds 200
[FgWin]::BringWindowToTop($hwnd) | Out-Null
[FgWin]::SetWindowPos($hwnd, [IntPtr]::Zero, 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0040) | Out-Null  # SWP_NOMOVE|NOSIZE|SHOWWINDOW
# Simulate an Alt press so the foreground lock is bypassed
[System.Windows.Forms.SendKeys]::SendWait("({ALT})") 2>$null
Start-Sleep -Milliseconds 150
[FgWin]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 300
$fg = [FgWin]::GetForegroundWindow()
Write-Output "HWND=$hwnd Foreground=$fg Match=$($fg -eq $hwnd)"
