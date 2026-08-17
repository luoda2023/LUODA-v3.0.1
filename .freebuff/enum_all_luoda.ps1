Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinAll2 {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  public struct RECT { public int L, T, R, B; }
  public static string Run() {
    var sb = new StringBuilder();
    EnumWindows((h, l) => {
      uint wp; GetWindowThreadProcessId(h, out wp);
      var t = new StringBuilder(256); GetWindowText(h, t, 256);
      var c = new StringBuilder(256); GetClassName(h, c, 256);
      RECT r; GetWindowRect(h, out r);
      sb.AppendLine(h + "|pid=" + wp + "|vis=" + IsWindowVisible(h) + "|" + c + "|" + t + "|" + r.L + "," + r.T + "," + r.R + "," + r.B);
      return true;
    }, IntPtr.Zero);
    return sb.ToString();
  }
}
'@
$pidList = (Get-Process luoda -ErrorAction SilentlyContinue | ForEach-Object { $_.Id }) -join '|'
$lines = [WinAll2]::Run().Split("`n") | Where-Object { $_ -match "pid=($pidList)\|" }
$lines
