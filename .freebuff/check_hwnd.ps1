Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class HwndProc {
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  public struct RECT { public int L, T, R, B; }
  public static string Info(IntPtr h) {
    uint pid; GetWindowThreadProcessId(h, out pid);
    var t = new StringBuilder(256);
    GetWindowText(h, t, 256);
    RECT r; GetWindowRect(h, out r);
    return "hwnd=" + h + " pid=" + pid + " title=" + t + " vis=" + IsWindowVisible(h) + " rect=" + r.L + "," + r.T + "," + r.R + "," + r.B;
  }
}
'@
$h = [IntPtr]2230128
Write-Output ("DotChatTest: " + [HwndProc]::Info($h))
$p = Get-Process -Id (([HwndProc]::Info($h) -split "pid=")[1] -split " ")[0] -ErrorAction SilentlyContinue
if ($p) { Write-Output ("Path: " + $p.Path) }
