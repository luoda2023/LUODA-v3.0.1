Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class WFP2 {
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public struct POINT { public int X, Y; }
  public struct RECT { public int L, T, R, B; }
}
"@
foreach ($pt in @(@(1063,191), @(880,728), @(1168,190), @(500,300), @(100,100), @(1300,500), @(1600,400))) {
  $p = New-Object WFP2+POINT
  $p.X = $pt[0]; $p.Y = $pt[1]
  $h = [WFP2]::WindowFromPoint($p)
  $r = New-Object WFP2+RECT
  [WFP2]::GetWindowRect($h, [ref]$r) | Out-Null
  $c = New-Object System.Text.StringBuilder 128
  $t = New-Object System.Text.StringBuilder 256
  [WFP2]::GetClassName($h, $c, 128) | Out-Null
  [WFP2]::GetWindowText($h, $t, 256) | Out-Null
  $pid2 = 0
  [WFP2]::GetWindowThreadProcessId($h, [ref]$pid2) | Out-Null
  Write-Host ("({0},{1}) -> hwnd={2} cls={3} title='{4}' pid={5} rect=({6},{7})-({8},{9})" -f $pt[0], $pt[1], $h, $c.ToString(), $t.ToString(), $pid2, $r.L, $r.T, $r.R, $r.B)
}
