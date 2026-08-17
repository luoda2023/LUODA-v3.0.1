Add-Type @'
using System;
using System.Runtime.InteropServices;
public class WinHelper {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  public struct RECT { public int L, T, R, B; }
  public static void Click(int x, int y) {
    SetCursorPos(x, y);
    System.Threading.Thread.Sleep(80);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(60);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }
  public static void Drag(int x1, int y1, int x2, int y2) {
    SetCursorPos(x1, y1);
    System.Threading.Thread.Sleep(80);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    int steps = 24;
    for (int i = 1; i <= steps; i++) {
      int x = x1 + (x2 - x1) * i / steps;
      int y = y1 + (y2 - y1) * i / steps;
      SetCursorPos(x, y);
      System.Threading.Thread.Sleep(12);
    }
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }
  public static void CtrlKey(bool down) {
    if (down) mouse_event(0x0008, 0, 0, 0, UIntPtr.Zero); // KEYDOWN
    else mouse_event(0x0008 | 0x0002, 0, 0, 0, UIntPtr.Zero); // KEYUP
  }
}
'@
$p = Get-Process luoda -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($p) {
  $r = New-Object WinHelper+RECT
  [WinHelper]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
  [WinHelper]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
  Write-Output "PID=$($p.Id) HWND=$($p.MainWindowHandle) Rect=$($r.L),$($r.T)-$($r.R),$($r.B) Visible=$([WinHelper]::IsWindowVisible($p.MainWindowHandle))"
}
