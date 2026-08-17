Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class ChildEnum {
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWndParent, EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr hWnd, ref POINT lpPoint);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public struct RECT { public int Left, Top, Right, Bottom; }
  public struct POINT { public int X, Y; }
}
"@
$cb = {
  param($h, $lp)
  $r = New-Object ChildEnum+RECT
  [ChildEnum]::GetWindowRect($h, [ref]$r) | Out-Null
  $cr = New-Object ChildEnum+RECT
  [ChildEnum]::GetClientRect($h, [ref]$cr) | Out-Null
  $len = [ChildEnum]::GetWindowTextLength($h)
  $sb = New-Object System.Text.StringBuilder($len + 1)
  [ChildEnum]::GetWindowText($h, $sb, $sb.Capacity) | Out-Null
  $vis = [ChildEnum]::IsWindowVisible($h)
  Write-Host ("child hwnd={0} vis={1} win={2},{3},{4},{5} client={6},{7} title={8}" -f $h, $vis, $r.Left, $r.Top, $r.Right, $r.Bottom, $cr.Right, $cr.Bottom, $sb.ToString())
  return $true
}
[ChildEnum]::EnumChildWindows([IntPtr]::new(787264), $cb, [IntPtr]::Zero) | Out-Null
