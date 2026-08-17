Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class ZOrder {
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  public struct RECT { public int L, T, R, B; }
  public static string List() {
    var sb = new StringBuilder();
    IntPtr h = GetWindow(IntPtr.Zero, 2); // GW_HWNDFIRST
    int i = 0;
    while (h != IntPtr.Zero && i < 30) {
      var t = new StringBuilder(256);
      GetWindowText(h, t, 256);
      RECT r; GetWindowRect(h, out r);
      sb.AppendLine(i + ": hwnd=" + h + " [" + t + "] " + r.L + "," + r.T + "," + r.R + "," + r.B);
      h = GetWindow(h, 3); // GW_HWNDNEXT
      i++;
    }
    return sb.ToString();
  }
}
'@
[ZOrder]::List()
