Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinCap2 {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$target = 10396
$cb = {
  param($h, $lp)
  $pid2 = 0
  [WinCap2]::GetWindowThreadProcessId($h, [ref]$pid2) | Out-Null
  if ($pid2 -eq $target) {
    $len = [WinCap2]::GetWindowTextLength($h)
    $sb = New-Object System.Text.StringBuilder($len+1)
    [WinCap2]::GetWindowText($h, $sb, $sb.Capacity) | Out-Null
    $r = New-Object WinCap2+RECT
    [WinCap2]::GetWindowRect($h, [ref]$r) | Out-Null
    Write-Output ("h={0} vis={1} title='{2}' rect={3},{4},{5},{6}" -f $h, [WinCap2]::IsWindowVisible($h), $sb.ToString(), $r.Left, $r.Top, $r.Right, $r.Bottom)
  }
  return $true
}
[WinCap2]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
Write-Output "done"