Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class TopWin {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public struct RECT { public int L, T, R, B; }
  public static string[] Dump() {
    System.Collections.Generic.List<string> out_ = new System.Collections.Generic.List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (!IsWindowVisible(h)) return true;
      StringBuilder sb = new StringBuilder(256);
      GetWindowText(h, sb, 256);
      RECT r; GetWindowRect(h, out r);
      out_.Add(string.Format("hwnd=0x{0:X} pid={1} rect={2},{3}-{4},{5} title='{6}'",
        h.ToInt64(), pid, r.L, r.T, r.R, r.B, sb.ToString()));
      return true;
    }, IntPtr.Zero);
    return out_.ToArray();
  }
}
'@
[TopWin]::Dump() | ForEach-Object { Write-Output $_ }
