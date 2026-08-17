param([int]$X, [int]$Y)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Input32b {
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int X; public int Y; }
  [StructLayout(LayoutKind.Sequential)]
  public struct MOUSEINPUT {
    public int dx; public int dy; public uint mouseData; public uint dwFlags;
    public uint time; public IntPtr dwExtraInfo;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT { public uint type; public MOUSEINPUT mi; }
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
}
'@
[Input32b]::SetCursorPos($X, $Y) | Out-Null
Start-Sleep -Milliseconds 200
$inputs = New-Object Input32b+INPUT[] 2
$inputs[0].type = 0
$inputs[0].mi.dwFlags = 0x0002
$inputs[0].mi.dx = 0; $inputs[0].mi.dy = 0; $inputs[0].mi.mouseData = 0; $inputs[0].mi.time = 0; $inputs[0].mi.dwExtraInfo = [IntPtr]::Zero
$inputs[1].type = 0
$inputs[1].mi.dwFlags = 0x0004
$inputs[1].mi.dx = 0; $inputs[1].mi.dy = 0; $inputs[1].mi.mouseData = 0; $inputs[1].mi.time = 0; $inputs[1].mi.dwExtraInfo = [IntPtr]::Zero
$sz = [System.Runtime.InteropServices.Marshal]::SizeOf([type][Input32b+INPUT])
[Input32b]::SendInput(2, $inputs, $sz) | Out-Null
Write-Host ("clicked " + $X + "," + $Y)
