Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinEnum3 {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  public struct RECT { public int L, T, R, B; }
  public static string List(uint targetPid) {
    var sb = new StringBuilder();
    EnumWindows((h, l) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid == targetPid) {
        var t = new StringBuilder(256);
        GetWindowText(h, t, 256);
        RECT r; GetWindowRect(h, out r);
        sb.AppendLine(h + "|vis=" + IsWindowVisible(h) + "|" + t + "|" + r.L + "," + r.T + "," + r.R + "," + r.B);
      }
      return true;
    }, IntPtr.Zero);
    return sb.ToString();
  }
}
'@
Get-Process luoda -ErrorAction SilentlyContinue | ForEach-Object {
  Write-Output ("PID=" + $_.Id)
  [WinEnum3]::List([uint32]$_.Id)
}
