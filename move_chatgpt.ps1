Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinMove2 {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
  public const uint SWP_NOZORDER = 0x0004;
  public const uint SWP_SHOWWINDOW = 0x0040;
  public static readonly IntPtr HWND_TOP = new IntPtr(0);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
# Move ChatGPT window to left half
[WinMove2]::SetWindowPos([IntPtr]132170, [WinMove2]::HWND_TOP, -7, -7, 1000, 1246, [WinMove2]::SWP_SHOWWINDOW) | Out-Null
Start-Sleep -Milliseconds 600
# Re-assert remote window on top of its region
[WinMove2]::SetForegroundWindow([IntPtr]526418) | Out-Null
Start-Sleep -Milliseconds 400
Write-Host "chatgpt moved left"
