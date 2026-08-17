Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinMove {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  public const uint SWP_NOZORDER = 0x0004;
  public const uint SWP_SHOWWINDOW = 0x0040;
  public static readonly IntPtr HWND_TOP = new IntPtr(0);
}
"@
# mstsc to top-left 50,50 1050x650
[WinMove]::SetWindowPos([IntPtr]198572, [WinMove]::HWND_TOP, 50, 50, 1050, 650, [WinMove]::SWP_NOZORDER -bor [WinMove]::SWP_SHOWWINDOW) | Out-Null
Start-Sleep -Milliseconds 400
# remote LDesk session to right side 1150,250 880x640
[WinMove]::SetWindowPos([IntPtr]526418, [WinMove]::HWND_TOP, 1150, 250, 880, 640, [WinMove]::SWP_SHOWWINDOW) | Out-Null
Start-Sleep -Milliseconds 400
# main LDesk to bottom-left 50,760 900x500
[WinMove]::SetWindowPos([IntPtr]592070, [WinMove]::HWND_TOP, 50, 760, 900, 500, [WinMove]::SWP_SHOWWINDOW) | Out-Null
Start-Sleep -Milliseconds 600
Write-Host "windows moved"
