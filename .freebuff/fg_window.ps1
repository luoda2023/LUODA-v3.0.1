Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinProc {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  public struct RECT { public int L, T, R, B; }
  public static string Info(IntPtr h) {
    uint pid; GetWindowThreadProcessId(h, out pid);
    var t = new StringBuilder(256);
    GetWindowText(h, t, 256);
    RECT r; GetWindowRect(h, out r);
    return "hwnd=" + h + " pid=" + pid + " title=" + t + " rect=" + r.L + "," + r.T + "," + r.R + "," + r.B;
  }
}
'@
$fg = [WinProc]::GetForegroundWindow()
Write-Output ("FOREGROUND: " + [WinProc]::Info($fg))
Get-Process | Where-Object { $_.ProcessName -match "luoda|ldesk|dot" } | ForEach-Object {
  Write-Output ("PROC: " + $_.Id + " " + $_.ProcessName + " " + $_.Path)
}
