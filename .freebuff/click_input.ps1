param(
  [int]$X = 0, [int]$Y = 0
)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class ClickInput {
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
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);

  static INPUT MakeMove(int x, int y) {
    int sw = GetSystemMetrics(0); int sh = GetSystemMetrics(1);
    INPUT i = new INPUT(); i.type = 0;
    i.U.mi.dx = (int)(x * 65535.0 / (sw - 1));
    i.U.mi.dy = (int)(y * 65535.0 / (sh - 1));
    i.U.mi.dwFlags = 0x0001 | 0x8000;
    return i;
  }
  static INPUT MakeButton(uint flags) {
    INPUT i = new INPUT(); i.type = 0;
    i.U.mi.dwFlags = flags;
    return i;
  }
  public static void Click(int x, int y) {
    INPUT[] arr = new INPUT[3];
    arr[0] = MakeMove(x, y);
    arr[1] = MakeButton(0x0002); // LEFTDOWN
    arr[2] = MakeButton(0x0004); // LEFTUP
    SendInput(3, arr, Marshal.SizeOf(typeof(INPUT)));
  }
}
'@
[ClickInput]::Click($X, $Y)
Write-Output "clicked ($X,$Y)"
