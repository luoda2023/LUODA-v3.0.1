Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WFP {
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  public struct POINT { public int X, Y; }
  public struct RECT { public int L, T, R, B; }
  public static string At(int x, int y) {
    var p = new POINT { X = x, Y = y };
    IntPtr h = WindowFromPoint(p);
    var t = new StringBuilder(256);
    GetWindowText(h, t, 256);
    uint pid; GetWindowThreadProcessId(h, out pid);
    return "pt=" + x + "," + y + " hwnd=" + h + " pid=" + pid + " [" + t + "]";
  }
}
'@
[WFP]::At(740, 587)
[WFP]::At(740, 906)
[WFP]::At(1513, 691)
[WFP]::At(700, 436)
