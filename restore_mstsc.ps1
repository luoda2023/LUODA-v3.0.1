Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinShow2 {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  public struct RECT { public int L, T, R, B; }
}
"@
$h = [IntPtr]198572
[WinShow2]::ShowWindow($h, 9) | Out-Null
[WinShow2]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 800
[WinShow2]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 500
$r = New-Object WinShow2+RECT
[WinShow2]::GetWindowRect($h, [ref]$r) | Out-Null
Write-Host ("mstsc rect: {0},{1}-{2},{3} iconic={4}" -f $r.L, $r.T, $r.R, $r.B, [WinShow2]::IsIconic($h))
