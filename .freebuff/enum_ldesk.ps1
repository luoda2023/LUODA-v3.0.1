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
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$procNames = @{}
Get-Process | ForEach-Object { $procNames[$_.Id] = $_.ProcessName }
$callback = {
  param($hwnd, $lparam)
  $len = [WinEnum2]::GetWindowTextLength($hwnd)
  if ($len -gt 0 -and [WinEnum2]::IsWindowVisible($hwnd)) {
    $sb = New-Object System.Text.StringBuilder($len + 1)
    [WinEnum2]::GetWindowText($hwnd, $sb, $sb.Capacity) | Out-Null
    $title = $sb.ToString()
    $rect = New-Object WinEnum2+RECT
    [WinEnum2]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    $processId = 0
    [WinEnum2]::GetWindowThreadProcessId($hwnd, [ref]$processId) | Out-Null
    $proc = $procNames[[int]$processId]
    if ($title -match "LDesk|远程|RustDesk|LUODA|DotChat|点聊" -or $proc -eq "LDesk") {
      Write-Host ("HWND={0} PID={1} PROC={2} RECT={3},{4},{5},{6} TITLE={7}" -f $hwnd, $processId, $proc, $rect.Left, $rect.Top, $rect.Right, $rect.Bottom, $title)
    }
  }
  return $true
}
[WinEnum2]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
