Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WE2 {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$targetPid = (Get-Process LDesk).Id
$cb = [WE2+EnumWindowsProc]{ param($hwnd,$lparam)
  $p=0; [WE2]::GetWindowThreadProcessId($hwnd,[ref]$p)|Out-Null
  if ($p -eq $targetPid) {
    $vis = [WE2]::IsWindowVisible($hwnd)
    $len=[WE2]::GetWindowTextLength($hwnd); $sb=New-Object System.Text.StringBuilder($len+1)
    [WE2]::GetWindowText($hwnd,$sb,$sb.Capacity)|Out-Null
    $wr=New-Object WE2+RECT; [WE2]::GetWindowRect($hwnd,[ref]$wr)|Out-Null
    $cr=New-Object WE2+RECT; [WE2]::GetClientRect($hwnd,[ref]$cr)|Out-Null
    if ($vis) { Write-Host ("VIS hwnd={0} wrect=({1},{2},{3},{4}) crect=({5},{6},{7},{8}) title='{9}'" -f $hwnd,$wr.Left,$wr.Top,$wr.Right,$wr.Bottom,$cr.Left,$cr.Top,$cr.Right,$cr.Bottom,$sb.ToString()) }
  }
  return $true
}
[WE2]::EnumWindows($cb,[IntPtr]::Zero)|Out-Null
