Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WE4 {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$proc = Get-Process LDesk -ErrorAction SilentlyContinue | Select-Object -First 1
$cb = {
  param($h2, $lp)
  $p = 0
  [WE4]::GetWindowThreadProcessId($h2, [ref]$p) | Out-Null
  if ($p -eq $proc.Id) {
    $l = [WE4]::GetWindowTextLength($h2)
    $sb = New-Object System.Text.StringBuilder($l + 1)
    if ($l -gt 0) { [WE4]::GetWindowText($h2, $sb, $sb.Capacity) | Out-Null }
    $r = New-Object WE4+RECT
    [WE4]::GetWindowRect($h2, [ref]$r) | Out-Null
    Write-Output ("hwnd={0} vis={1} rect={2},{3},{4},{5} title={6}" -f $h2, [WE4]::IsWindowVisible($h2), $r.Left, $r.Top, $r.Right, $r.Bottom, $sb.ToString())
  }
  return $true
}
[WE4]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
