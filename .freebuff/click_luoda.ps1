param([int]$X = 0, [int]$Y = 0, [int]$Hwnd = 0)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class ClickTop2 {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT { public uint type; public InputUnion U; }
  [StructLayout(LayoutKind.Explicit)]
  public struct InputUnion { [FieldOffset(0)] public MOUSEINPUT mi; }
  [StructLayout(LayoutKind.Sequential)]
  public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] p, int cb);
}
'@
$h = [IntPtr]$Hwnd
if ($Hwnd -ne 0) {
  [ClickTop2]::ShowWindow($h, 9) | Out-Null
  [ClickTop2]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0040) | Out-Null  # TOPMOST
  Start-Sleep -Milliseconds 250
}
$sz = [System.Runtime.InteropServices.Marshal]::SizeOf([type][ClickTop2+INPUT])
$input = New-Object ClickTop2+INPUT
$input.type = 0
$input.U.mi.dx = $X; $input.U.mi.dy = $Y
$input.U.mi.mouseData = 0; $input.U.mi.time = 0
$input.U.mi.dwExtraInfo = [IntPtr]::Zero
$input.U.mi.dwFlags = 0x0001
[ClickTop2]::SendInput(1, @($input), $sz) | Out-Null
$input.U.mi.dwFlags = 0x0002
[ClickTop2]::SendInput(1, @($input), $sz) | Out-Null
$input.U.mi.dwFlags = 0x0004
[ClickTop2]::SendInput(1, @($input), $sz) | Out-Null
"clicked $X,$Y"
