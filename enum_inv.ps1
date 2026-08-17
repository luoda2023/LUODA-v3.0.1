Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinEnumInv {
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
$procId = 20492
$results = New-Object System.Collections.ArrayList
$cb = [WinEnumInv+EnumWindowsProc]{
  param($hwnd, $lparam)
  $p = 0
  [WinEnumInv]::GetWindowThreadProcessId($hwnd, [ref]$p) | Out-Null
  if ($p -eq $procId) {
    $len = [WinEnumInv]::GetWindowTextLength($hwnd)
    $sb = New-Object System.Text.StringBuilder([Math]::Max($len,1) + 1)
    [WinEnumInv]::GetWindowText($hwnd, $sb, $sb.Capacity) | Out-Null
    $rect = New-Object WinEnumInv+RECT
    [WinEnumInv]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    [void]$results.Add(("HWND={0} VIS={1} RECT={2},{3},{4},{5} TITLE='{6}'" -f $hwnd, [WinEnumInv]::IsWindowVisible($hwnd), $rect.Left, $rect.Top, $rect.Right, $rect.Bottom, $sb.ToString()))
  }
  return $true
}
[WinEnumInv]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$results | ForEach-Object { Write-Host $_ }
