$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinFocus3 {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder s, int n);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
}
"@
$proc = Get-Process LDesk -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { Write-Output "NO LDESK"; exit 1 }
$targetPid = $proc.Id
$found = @()
$cb = { param($h2, $lp) $p=0; [WinFocus3]::GetWindowThreadProcessId($h2, [ref]$p) | Out-Null; if ($p -eq $targetPid) { $l=[WinFocus3]::GetWindowTextLength($h2); if ($l -gt 0) { $sb=New-Object System.Text.StringBuilder($l+1); [WinFocus3]::GetWindowText($h2,$sb,$sb.Capacity) | Out-Null; $script:found += @{hwnd=$h2; title=$sb.ToString()} } }; return $true }
[WinFocus3]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
# focus the Remote Desktop window (title contains 'Remote Desktop')
$remote = $found | Where-Object { $_.title -match 'Remote Desktop' } | Select-Object -First 1
$h = [IntPtr]$remote.hwnd
Write-Output "remote hwnd=$h title=$($remote.title)"
if ($h -ne [IntPtr]::Zero) {
  [WinFocus3]::ShowWindow($h, 9) | Out-Null
  [WinFocus3]::SetForegroundWindow($h) | Out-Null
  Start-Sleep -Milliseconds 400
  [WinFocus3]::BringWindowToTop($h) | Out-Null
  [WinFocus3]::SetForegroundWindow($h) | Out-Null
  Start-Sleep -Milliseconds 800
}
Write-Output "focused"
