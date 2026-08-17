param([string]$Out = "J:\codex-work\LUODA-v3.0.1\.freebuff\pw_dyn.png", [int]$Nudge = 0)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class PWD {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool RedrawWindow(IntPtr h, IntPtr r, IntPtr hr, uint f);
  public struct RECT { public int L, T, R, B; }
  public static IntPtr FindMain() {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      StringBuilder sb = new StringBuilder(128);
      GetClassName(h, sb, 128);
      if (sb.ToString() == "FLUTTER_RUNNER_WIN32_WINDOW" && IsWindowVisible(h)) found = h;
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
'@
$main = [PWD]::FindMain()
if ($main -eq [IntPtr]::Zero) { Write-Output "NO_MAIN"; exit 1 }
$r = New-Object PWD+RECT
[PWD]::GetWindowRect($main, [ref]$r) | Out-Null
Write-Output ("main rect={0},{1},{2},{3} size={4}x{5}" -f $r.L,$r.T,$r.R,$r.B,($r.R-$r.L),($r.B-$r.T))
if ($Nudge -eq 1) {
  [PWD]::SetWindowPos($main, [IntPtr]::Zero, $r.L+1, $r.T, 0, 0, 0x0001 -bor 0x0004) | Out-Null  # SWP_NOSIZE|SWP_NOZORDER
  Start-Sleep -Milliseconds 120
  [PWD]::SetWindowPos($main, [IntPtr]::Zero, $r.L, $r.T, 0, 0, 0x0001 -bor 0x0004) | Out-Null
  Start-Sleep -Milliseconds 200
}
$w = $r.R - $r.L; $h = $r.B - $r.T
if ($w -le 0 -or $h -le 0) { Write-Output "bad size"; exit 1 }
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[PWD]::PrintWindow($main, $hdc, 2) | Out-Null
$g.ReleaseHdc($hdc)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "saved $Out"
