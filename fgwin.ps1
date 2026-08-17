Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class FgWin {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  public struct RECT { public int L, T, R, B; }
}
"@
$fg = [FgWin]::GetForegroundWindow()
$pid2 = 0
[FgWin]::GetWindowThreadProcessId($fg, [ref]$pid2) | Out-Null
$sb = New-Object System.Text.StringBuilder(256)
[FgWin]::GetWindowText($fg, $sb, 256) | Out-Null
Write-Host "Foreground: HWND=$fg PID=$pid2 TITLE=$($sb.ToString())"
$p = New-Object FgWin+POINT
$p.X = 1430; $p.Y = 588
$h = [FgWin]::WindowFromPoint($p)
$pid3 = 0
[FgWin]::GetWindowThreadProcessId($h, [ref]$pid3) | Out-Null
$sb2 = New-Object System.Text.StringBuilder(256)
[FgWin]::GetWindowText($h, $sb2, 256) | Out-Null
Write-Host "Window under (1430,588): HWND=$h PID=$pid3 TITLE=$($sb2.ToString())"
$p2 = New-Object FgWin+POINT
$p2.X = 1100; $p2.Y = 700
$h2 = [FgWin]::WindowFromPoint($p2)
$pid4 = 0
[FgWin]::GetWindowThreadProcessId($h2, [ref]$pid4) | Out-Null
$sb3 = New-Object System.Text.StringBuilder(256)
[FgWin]::GetWindowText($h2, $sb3, 256) | Out-Null
Write-Host "Window under (1100,700): HWND=$h2 PID=$pid4 TITLE=$($sb3.ToString())"
