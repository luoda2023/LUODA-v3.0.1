param([int]$CX = 0, [int]$CY = 0, [int]$DX = 0, [int]$DY = 0)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class PM3 {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wp, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr hWnd, ref POINT lpPoint);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  public struct RECT { public int L, T, R, B; }
  public struct POINT { public int X, Y; }

  public static IntPtr FindMain() {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      StringBuilder sb = new StringBuilder(128);
      GetClassName(h, sb, 128);
      if (sb.ToString() == "FLUTTER_RUNNER_WIN32_WINDOW" && IsWindowVisible(h)) found = h;
      return true;
    }, IntPtr.Zero);
    return found;
  }
  public static IntPtr FindView(IntPtr main) {
    IntPtr found = IntPtr.Zero;
    EnumChildWindows(main, delegate(IntPtr h, IntPtr l) {
      StringBuilder sb = new StringBuilder(128);
      GetClassName(h, sb, 128);
      if (sb.ToString() == "FLUTTERVIEW") { found = h; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }
  public static string Click(int sx, int sy, int ddx, int ddy) {
    IntPtr main = FindMain();
    if (main == IntPtr.Zero) return "NO_MAIN";
    IntPtr fv = FindView(main);
    if (fv == IntPtr.Zero) return "NO_FV";
    RECT r; GetWindowRect(fv, out r);
    POINT pt = new POINT(); pt.X = sx; pt.Y = sy;
    ScreenToClient(fv, ref pt);
    ShowWindow(main, 9); SetForegroundWindow(main);
    System.Threading.Thread.Sleep(300);
    IntPtr lp = (IntPtr)(((pt.Y & 0xFFFF) << 16) | (pt.X & 0xFFFF));
    PostMessage(fv, 0x0200, IntPtr.Zero, lp);
    System.Threading.Thread.Sleep(80);
    PostMessage(fv, 0x0201, (IntPtr)1, lp);
    System.Threading.Thread.Sleep(120);
    PostMessage(fv, 0x0202, IntPtr.Zero, lp);
    if (ddx != 0 || ddy != 0) {
      POINT pt2 = new POINT(); pt2.X = ddx; pt2.Y = ddy;
      ScreenToClient(fv, ref pt2);
      int steps = 14;
      for (int i = 1; i <= steps; i++) {
        int mx = pt.X + (int)((pt2.X - pt.X) * i / (double)steps);
        int my = pt.Y + (int)((pt2.Y - pt.Y) * i / (double)steps);
        PostMessage(fv, 0x0200, (IntPtr)1, (IntPtr)(((my & 0xFFFF) << 16) | (mx & 0xFFFF)));
        System.Threading.Thread.Sleep(30);
      }
      PostMessage(fv, 0x0202, IntPtr.Zero, (IntPtr)(((pt2.Y & 0xFFFF) << 16) | (pt2.X & 0xFFFF)));
    }
    return "OK fv=" + fv + " rect=" + r.L + "," + r.T + "," + r.R + "," + r.B + " client=(" + pt.X + "," + pt.Y + ")";
  }
}
'@
[PM3]::Click($CX, $CY, $DX, $DY)
