param(
  [int]$X1 = 0, [int]$Y1 = 0,
  [int]$X2 = 0, [int]$Y2 = 0,
  [int]$Steps = 40
)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class DragInput {
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int x; public int y; }
  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT {
    public uint type;
    public InputUnion U;
  }
  [StructLayout(LayoutKind.Explicit)]
  public struct InputUnion {
    [FieldOffset(0)] public MOUSEINPUT mi;
    [FieldOffset(0)] public KEYBDINPUT ki;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct MOUSEINPUT {
    public int dx; public int dy;
    public uint mouseData; public uint dwFlags;
    public uint time; public IntPtr dwExtraInfo;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct KEYBDINPUT {
    public ushort wVk; public ushort wScan;
    public uint dwFlags; public uint time;
    public IntPtr dwExtraInfo;
  }
  [DllImport("user32.dll")] public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
  [DllImport("user32.dll")] public static extern bool GetSystemMetrics_(int nIndex);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);

  public static void Move(int x, int y) {
    int sw = GetSystemMetrics(0); int sh = GetSystemMetrics(1);
    INPUT i = new INPUT();
    i.type = 0; // INPUT_MOUSE
    i.U.mi.dx = (int)(x * 65535.0 / (sw - 1));
    i.U.mi.dy = (int)(y * 65535.0 / (sh - 1));
    i.U.mi.dwFlags = 0x0001 | 0x8000; // MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE
    INPUT[] arr = new INPUT[1]; arr[0] = i;
    SendInput(1, arr, Marshal.SizeOf(typeof(INPUT)));
  }
  public static void Down() {
    INPUT i = new INPUT(); i.type = 0;
    i.U.mi.dwFlags = 0x0002; // LEFTDOWN
    INPUT[] arr = new INPUT[1]; arr[0] = i;
    SendInput(1, arr, Marshal.SizeOf(typeof(INPUT)));
  }
  public static void Up() {
    INPUT i = new INPUT(); i.type = 0;
    i.U.mi.dwFlags = 0x0004; // LEFTUP
    INPUT[] arr = new INPUT[1]; arr[0] = i;
    SendInput(1, arr, Marshal.SizeOf(typeof(INPUT)));
  }
  public static void Drag(int x1, int y1, int x2, int y2, int steps) {
    Move(x1, y1);
    System.Threading.Thread.Sleep(120);
    Down();
    System.Threading.Thread.Sleep(80);
    for (int s = 1; s <= steps; s++) {
      int x = x1 + (x2 - x1) * s / steps;
      int y = y1 + (y2 - y1) * s / steps;
      Move(x, y);
      System.Threading.Thread.Sleep(16);
    }
    System.Threading.Thread.Sleep(80);
    Up();
  }
}
'@
[DragInput]::Drag($X1, $Y1, $X2, $Y2, $Steps)
Write-Output "dragged ($X1,$Y1)->($X2,$Y2)"
