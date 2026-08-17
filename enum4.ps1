Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinEnum3 {
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
$script:results = New-Object System.Collections.ArrayList
$callback = {
  param($hwnd, $lparam)
  $len = [WinEnum3]::GetWindowTextLength($hwnd)
  $procId = 0
  [WinEnum3]::GetWindowThreadProcessId($hwnd, [ref]$procId) | Out-Null
  if ($procId -eq 20492 -and $len -gt 0 -and [WinEnum3]::IsWindowVisible($hwnd)) {
    $sb = New-Object System.Text.StringBuilder($len + 1)
    [WinEnum3]::GetWindowText($hwnd, $sb, $sb.Capacity) | Out-Null
    $rect = New-Object WinEnum3+RECT
    [WinEnum3]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    [void]$script:results.Add(("HWND={0} RECT={1},{2},{3},{4} TITLE={5}" -f $hwnd, $rect.Left, $rect.Top, $rect.Right, $rect.Bottom, $sb.ToString()))
  }
  return $true
}
[WinEnum3]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
$script:results | ForEach-Object { Write-Host $_ }

