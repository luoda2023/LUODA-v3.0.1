param(
  [int]$X = 0,
  [int]$Y = 0,
  [int]$X2 = -1,
  [int]$Y2 = -1,
  [string]$Action = "click"   # click | drag
)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class WinInput {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  public static void Click(int x, int y) {
    SetCursorPos(x, y);
    System.Threading.Thread.Sleep(100);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(60);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }
  public static void Drag(int x1, int y1, int x2, int y2) {
    SetCursorPos(x1, y1);
    System.Threading.Thread.Sleep(100);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    int steps = 30;
    for (int i = 1; i <= steps; i++) {
      int x = x1 + (x2 - x1) * i / steps;
      int y = y1 + (y2 - y1) * i / steps;
      SetCursorPos(x, y);
      System.Threading.Thread.Sleep(10);
    }
    System.Threading.Thread.Sleep(80);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }
}
'@
if ($Action -eq "drag") {
  [WinInput]::Drag($X, $Y, $X2, $Y2)
  Write-Output "dragged ($X,$Y)->($X2,$Y2)"
} else {
  [WinInput]::Click($X, $Y)
  Write-Output "clicked ($X,$Y)"
}
