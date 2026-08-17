Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinFocus {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$remote = [IntPtr]526418
[WinFocus]::ShowWindow($remote, 9) | Out-Null
[WinFocus]::SetForegroundWindow($remote) | Out-Null
Start-Sleep -Milliseconds 500
[WinFocus]::BringWindowToTop($remote) | Out-Null
[WinFocus]::SetForegroundWindow($remote) | Out-Null
Start-Sleep -Milliseconds 500
$r = New-Object WinFocus+RECT
[WinFocus]::GetWindowRect($remote, [ref]$r) | Out-Null
Write-Host ("remote rect: {0},{1},{2},{3}" -f $r.Left, $r.Top, $r.Right, $r.Bottom)
