Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Styles {
  [DllImport("user32.dll", SetLastError=true)] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetWindowText(IntPtr hWnd, System.Text.StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  public struct RECT { public int L, T, R, B; }
  public static string Info(IntPtr h) {
    int ex = GetWindowLong(h, -20); // GWL_EXSTYLE
    int st = GetWindowLong(h, -16); // GWL_STYLE
    bool topmost = (ex & 0x8) != 0; // WS_EX_TOPMOST
    RECT r; GetWindowRect(h, out r);
    var t = new System.Text.StringBuilder(256);
    GetWindowText(h, t, 256);
    uint pid; GetWindowThreadProcessId(h, out pid);
    return "hwnd=" + h + " pid=" + pid + " title=[" + t + "] topmost=" + topmost + " exstyle=0x" + ex.ToString("X") + " style=0x" + st.ToString("X") + " rect=" + r.L + "," + r.T + "," + r.R + "," + r.B;
  }
}
'@
[Styles]::Info([IntPtr]3935734)   # LDesk
[Styles]::Info([IntPtr]5837650)   # Freebuff Desktop
