Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinEnum {
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
$procIds = @{}
Get-Process | ForEach-Object { $procIds[$_.Id] = $_.ProcessName }
$callback = {
  param($hwnd, $lparam)
  $len = [WinEnum]::GetWindowTextLength($hwnd)
  if ($len -gt 0 -and [WinEnum]::IsWindowVisible($hwnd)) {
    $sb = New-Object System.Text.StringBuilder($len + 1)
    [WinEnum]::GetWindowText($hwnd, $sb, $sb.Capacity) | Out-Null
    $title = $sb.ToString()
    $rect = New-Object WinEnum+RECT
    [WinEnum]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    $pid = 0
    [WinEnum]::GetWindowThreadProcessId($hwnd, [ref]$pid) | Out-Null
    $proc = $procIds[[int]$pid]
    if ($title -match "LDesk|远程|RustDesk|LUODA|2233|980966|423727") {
      Write-Host ("PID={0} PROC={1} RECT={2},{3},{4},{5} TITLE={6}" -f $pid, $proc, $rect.Left, $rect.Top, $rect.Right, $rect.Bottom, $title)
    }
  }
  return $true
}
[WinEnum]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
