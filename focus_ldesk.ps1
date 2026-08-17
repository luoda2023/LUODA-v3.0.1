Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinFocus2 {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$hWnd = [IntPtr]::Zero
$callback = {
  param($h, $lp)
  $pid2 = 0
  [WinFocus2]::GetWindowThreadProcessId($h, [ref]$pid2) | Out-Null
  if ($pid2 -eq 23692) { $script:hWnd = $h; return $false }
  return $true
}
[WinFocus2]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
Write-Host "hWnd=$hWnd"
if ($hWnd -ne [IntPtr]::Zero) {
  [WinFocus2]::ShowWindow($hWnd, 9) | Out-Null
  [WinFocus2]::SetForegroundWindow($hWnd) | Out-Null
  Start-Sleep -Milliseconds 400
  [WinFocus2]::BringWindowToTop($hWnd) | Out-Null
  [WinFocus2]::SetForegroundWindow($hWnd) | Out-Null
  Start-Sleep -Milliseconds 600
  $r = New-Object WinFocus2+RECT
  [WinFocus2]::GetWindowRect($hWnd, [ref]$r) | Out-Null
  Write-Host ("rect: {0},{1},{2},{3}" -f $r.Left, $r.Top, $r.Right, $r.Bottom)
}
