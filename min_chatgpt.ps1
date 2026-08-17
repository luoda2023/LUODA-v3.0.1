Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinChk {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  public struct RECT { public int L, T, R, B; }
}
"@
$r = New-Object WinChk+RECT
[WinChk]::GetWindowRect([IntPtr]132170, [ref]$r) | Out-Null
Write-Host ("ChatGPT rect: {0},{1}-{2},{3} iconic={4}" -f $r.L, $r.T, $r.R, $r.B, [WinChk]::IsIconic([IntPtr]132170))
[WinChk]::ShowWindow([IntPtr]132170, 6) | Out-Null  # SW_MINIMIZE
Start-Sleep -Milliseconds 800
Write-Host ("After minimize iconic={0}" -f [WinChk]::IsIconic([IntPtr]132170))
