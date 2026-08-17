Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinTop {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  public const uint SWP_NOSIZE = 0x0001;
  public const uint SWP_NOMOVE = 0x0002;
  public const uint SWP_NOACTIVATE = 0x0010;
  public const uint SWP_SHOWWINDOW = 0x0040;
  public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
}
"@
# bring remote window to topmost
[WinTop]::SetWindowPos([IntPtr]526418, [WinTop]::HWND_TOPMOST, 442, 236, 0, 0, [WinTop]::SWP_NOSIZE -bor [WinTop]::SWP_SHOWWINDOW) | Out-Null
Start-Sleep -Milliseconds 800
Write-Host "remote window topmost"
