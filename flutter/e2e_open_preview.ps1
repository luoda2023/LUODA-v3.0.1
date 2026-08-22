# One-shot: bring main LUODA window to front, click the image bubble,
# wait for a new RustdeskMultiWindow, bring IT to front, report its rect.
param(
  [int]$ImgX = 1750,
  [int]$ImgY = 850
)
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class E2E {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern IntPtr FindWindowW(string cls, string title);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] private static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr h, [MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetClassNameW(IntPtr h, [MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  public static List<long> FindClass(string cls) {
    var list = new List<long>();
    EnumWindows((h, l) => {
      var c = new StringBuilder(256); GetClassNameW(h, c, 256);
      if (c.ToString() == cls && IsWindowVisible(h)) list.Add(h.ToInt64());
      return true;
    }, IntPtr.Zero);
    return list;
  }
  public static string RectOf(long h) {
    RECT r; GetWindowRect((IntPtr)h, out r);
    return r.L + "," + r.T + " " + (r.R - r.L) + "x" + (r.B - r.T);
  }
  public static string TitleOf(long h) {
    var t = new StringBuilder(256); GetWindowTextW((IntPtr)h, t, 256); return t.ToString();
  }
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public static void Click(int x, int y) {
    SetCursorPos(x, y); System.Threading.Thread.Sleep(150);
    mouse_event(2, 0, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(60);
    mouse_event(4, 0, 0, 0, UIntPtr.Zero);
  }
}
'@
$ErrorActionPreference = 'Continue'

# 1. Find the main LUODA window (class starts with Flutter runner win32 class)
$mainHwnd = [IntPtr]::Zero
$mains = [E2E]::FindClass('FLUTTER_RUNNER_WIN32_WINDOW')
if ($mains.Count -gt 0) { $mainHwnd = [IntPtr]$mains[0] }
if ($mainHwnd -eq [IntPtr]::Zero) {
  # fallback: any window whose class contains FLUTTER
  Write-Output 'MAIN_WINDOW_NOT_FOUND'; exit 1
}
Write-Output ('MAIN=' + $mainHwnd + ' title=' + [E2E]::TitleOf($mainHwnd.ToInt64()) + ' rect=' + [E2E]::RectOf($mainHwnd.ToInt64()))

# 2. Foreground main, then click the image bubble
[E2E]::ShowWindow($mainHwnd, 9) | Out-Null
[E2E]::SetForegroundWindow($mainHwnd) | Out-Null
Start-Sleep -Milliseconds 600
$before = [E2E]::FindClass('RustdeskMultiWindow')
Write-Output ('PREVIEW_BEFORE=' + $before.Count)

[E2E]::Click($ImgX, $ImgY)
Start-Sleep -Milliseconds 2500

$after = [E2E]::FindClass('RustdeskMultiWindow')
Write-Output ('PREVIEW_AFTER=' + $after.Count)

if ($after.Count -gt 0) {
  $newH = [IntPtr]$after[0]
  [E2E]::ShowWindow($newH, 9) | Out-Null
  [E2E]::SetForegroundWindow($newH) | Out-Null
  Start-Sleep -Milliseconds 700
  Write-Output ('NEW_PREVIEW handle=' + $newH + ' title=' + [E2E]::TitleOf($newH.ToInt64()) + ' rect=' + [E2E]::RectOf($newH.ToInt64()))
  Write-Output ('FOREGROUND_IS_NEW=' + (([E2E]::GetForegroundWindow()) -eq $newH))
} else {
  Write-Output 'NO_PREVIEW_OPENED'
}
