# Enumerate visible top-level windows: handle | class | title | rect
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WinList {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr h, [MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetClassNameW(IntPtr h, [MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  public static string Out = "";
  public static bool Cb(IntPtr h, IntPtr l) {
    if (IsWindowVisible(h)) {
      var t = new StringBuilder(256); GetWindowTextW(h, t, 256);
      var c = new StringBuilder(256); GetClassNameW(h, c, 256);
      RECT r; GetWindowRect(h, out r);
      if (t.Length > 0 && (r.R - r.L) > 100 && (r.B - r.T) > 80)
        Out += h.ToInt64() + "|" + c.ToString() + "|" + t.ToString() + "|" + r.L + "," + r.T + " " + (r.R - r.L) + "x" + (r.B - r.T) + "\n";
    }
    return true;
  }
  public static string Run() { EnumWindows(Cb, IntPtr.Zero); return Out; }
}
'@
Write-Output ([WinList]::Run())
