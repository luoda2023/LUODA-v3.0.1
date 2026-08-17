param([int]$X = 0, [int]$Y = 0)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class ClickPt {
  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT { public uint type; public InputUnion U; }
  [StructLayout(LayoutKind.Explicit)]
  public struct InputUnion { [FieldOffset(0)] public MOUSEINPUT mi; }
  [StructLayout(LayoutKind.Sequential)]
  public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] p, int cb);
}
'@
$sz = [System.Runtime.InteropServices.Marshal]::SizeOf([type][ClickPt+INPUT])
$input = New-Object ClickPt+INPUT
$input.type = 0
$input.U.mi.dx = $X; $input.U.mi.dy = $Y
$input.U.mi.mouseData = 0; $input.U.mi.time = 0
$input.U.mi.dwExtraInfo = [IntPtr]::Zero
$input.U.mi.dwFlags = 0x0001
[ClickPt]::SendInput(1, @($input), $sz) | Out-Null
$input.U.mi.dwFlags = 0x0002
[ClickPt]::SendInput(1, @($input), $sz) | Out-Null
$input.U.mi.dwFlags = 0x0004
[ClickPt]::SendInput(1, @($input), $sz) | Out-Null
Write-Output "clicked $X,$Y"
