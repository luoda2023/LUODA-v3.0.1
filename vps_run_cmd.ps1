$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KB {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] ins, int sz);
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public InputUnion U; }
  [StructLayout(LayoutKind.Explicit)] public struct InputUnion { [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public UIntPtr dwExtraInfo; }
  public struct RECT { public int Left, Top, Right, Bottom; }
  public const uint INPUT_KEYBOARD = 1;
  public const uint KEYEVENTF_UNICODE = 0x0004;
  public const uint KEYEVENTF_KEYUP = 0x0002;
  public const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
  public static void Key(ushort vk, bool up = false) {
    INPUT[] i = new INPUT[1];
    i[0].type = INPUT_KEYBOARD; i[0].U.ki.wVk = vk; i[0].U.ki.wScan = 0; i[0].U.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0; i[0].U.ki.time = 0;
    SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
  }
  public static void Uni(string s) {
    foreach (char c in s) {
      INPUT[] d = new INPUT[1]; d[0].type = INPUT_KEYBOARD; d[0].U.ki.wVk = 0; d[0].U.ki.wScan = (ushort)c; d[0].U.ki.dwFlags = KEYEVENTF_UNICODE; d[0].U.ki.time = 0;
      INPUT[] u = new INPUT[1]; u[0].type = INPUT_KEYBOARD; u[0].U.ki.wVk = 0; u[0].U.ki.wScan = (ushort)c; u[0].U.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP; u[0].U.ki.time = 0;
      SendInput(1, d, Marshal.SizeOf(typeof(INPUT))); SendInput(1, u, Marshal.SizeOf(typeof(INPUT)));
    }
  }
  public static void Chord(params ushort[] keys) {
    foreach (var k in keys) Key(k);
    for (int i = keys.Length - 1; i >= 0; i--) Key(keys[i], true);
  }
}
"@
$h = [IntPtr]4917734
[KB]::ShowWindow($h, 9) | Out-Null
[KB]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 600
# Win+R on VPS
[KB]::Key(0x5B); [KB]::Key(0x52); [KB]::Key(0x52, $true); [KB]::Key(0x5B, $true)
Start-Sleep -Milliseconds 800
[KB]::Uni("cmd")
Start-Sleep -Milliseconds 300
[KB]::Key(0x0D); [KB]::Key(0x0D, $true)  # Enter
Start-Sleep -Milliseconds 1200
Write-Output "sent Win+R cmd"
