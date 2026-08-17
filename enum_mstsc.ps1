Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinEnum5 {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$script:rows = New-Object System.Collections.ArrayList
$fg = [WinEnum5]::GetForegroundWindow()
$callback = {
  param($hwnd, $lparam)
  $len = [WinEnum5]::GetWindowTextLength($hwnd)
  $procId = 0
  [WinEnum5]::GetWindowThreadProcessId($hwnd, [ref]$procId) | Out-Null
  if ($procId -eq 13248 -and $len -gt 0) {
    $sb = New-Object System.Text.StringBuilder($len + 1)
    [WinEnum5]::GetWindowText($hwnd, $sb, $sb.Capacity) | Out-Null
    $rect = New-Object WinEnum5+RECT
    [WinEnum5]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    $fgmark = if ($hwnd -eq $fg) { " [FOREGROUND]" } else { "" }
    [void]$script:rows.Add(("HWND={0} VIS={1} RECT={2},{3}-{4},{5} {6}{7}" -f $hwnd, [WinEnum5]::IsWindowVisible($hwnd), $rect.Left, $rect.Top, $rect.Right, $rect.Bottom, $sb.ToString(), $fgmark))
  }
  return $true
}
[WinEnum5]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
$script:rows | ForEach-Object { Write-Host $_ }
Write-Host "FG=$fg"
