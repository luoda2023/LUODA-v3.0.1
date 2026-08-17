Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinEnum2 {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$script:results = New-Object System.Collections.ArrayList
$callback = {
  param($hwnd, $lparam)
  $len = [WinEnum2]::GetWindowTextLength($hwnd)
  $procId = 0
  [WinEnum2]::GetWindowThreadProcessId($hwnd, [ref]$procId) | Out-Null
  if (($procId -eq 4088 -or $procId -eq 13248) -and $len -gt 0) {
    $sb = New-Object System.Text.StringBuilder($len + 1)
    [WinEnum2]::GetWindowText($hwnd, $sb, $sb.Capacity) | Out-Null
    $rect = New-Object WinEnum2+RECT
    [WinEnum2]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    $vis = [WinEnum2]::IsWindowVisible($hwnd)
    $iconic = [WinEnum2]::IsIconic($hwnd)
    [void]$script:results.Add(("HWND={0} PID={1} VIS={2} ICON={3} RECT={4},{5},{6},{7} TITLE={8}" -f $hwnd, $procId, $vis, $iconic, $rect.Left, $rect.Top, $rect.Right, $rect.Bottom, $sb.ToString()))
  }
  return $true
}
[WinEnum2]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
$script:results | ForEach-Object { Write-Host $_ }
