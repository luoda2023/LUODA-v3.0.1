param([int]$X = 0, [int]$Y = 0)
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinAt {
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public struct POINT { public int X, Y; }
  public struct RECT { public int L, T, R, B; }
}
'@
$pt = New-Object WinAt+POINT
$pt.X = $X; $pt.Y = $Y
$h = [WinAt]::WindowFromPoint($pt)
if ($h -eq [IntPtr]::Zero) { "NONE"; exit }
$pid0 = 0
[WinAt]::GetWindowThreadProcessId($h, [ref]$pid0) | Out-Null
$c = New-Object System.Text.StringBuilder 128
[WinAt]::GetClassName($h, $c, 128) | Out-Null
$t = New-Object System.Text.StringBuilder 256
[WinAt]::GetWindowText($h, $t, 256) | Out-Null
$r = New-Object WinAt+RECT
[WinAt]::GetWindowRect($h, [ref]$r) | Out-Null
"hwnd=$h pid=$pid0 class=$($c.ToString()) title=$($t.ToString()) rect=$($r.L),$($r.T),$($r.R),$($r.B)"
