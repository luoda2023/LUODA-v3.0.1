param([int]$ProcId)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Fg {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string title);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  public static IntPtr MainOf(int pid) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p == (uint)pid) { found = h; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
'@
$h = [Fg]::MainOf($ProcId)
if ($h -eq [IntPtr]::Zero) { Write-Output "NOHWND"; exit }
if ([Fg]::IsIconic($h)) { [Fg]::ShowWindow($h, 9) | Out-Null }
[Fg]::SetForegroundWindow($h) | Out-Null
Write-Output "OK hwnd=$h"
