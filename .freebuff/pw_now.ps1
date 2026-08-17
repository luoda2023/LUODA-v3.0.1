$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class PN {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
  public struct RECT { public int Left, Top, Right, Bottom; }
  public static System.Drawing.Bitmap CapturePW(IntPtr hwnd) {
    RECT r; GetWindowRect(hwnd, out r);
    int w = r.Right - r.Left, h = r.Bottom - r.Top;
    System.Drawing.Bitmap bmp = new System.Drawing.Bitmap(w, h);
    using (System.Drawing.Graphics g = System.Drawing.Graphics.FromImage(bmp)) {
      IntPtr hdc = g.GetHdc();
      PrintWindow(hwnd, hdc, 2);
      g.ReleaseHdc(hdc);
    }
    return bmp;
  }
}
"@
$script:main = [IntPtr]::Zero
$cb = {
  param($h, $lp)
  $sb = New-Object System.Text.StringBuilder 128
  [PN]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTER_RUNNER_WIN32_WINDOW" -and [PN]::IsWindowVisible($h)) {
    $p = 0; [PN]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
    if ($p -eq 20180) { $script:main = $h; return $false }
  }
  return $true
}
[PN]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$bmp = [PN]::CapturePW($script:main)
$bmp.Save("$PSScriptRoot\pw_now.png", [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("PW captured {0}x{1}" -f $bmp.Width, $bmp.Height)
# also list rects of known windows
foreach ($w in @(787264, 919178, 919098, 655948, 853348, 394982, 394756)) {
  $r = New-Object PN+RECT
  if ([PN]::GetWindowRect([IntPtr]$w, [ref]$r)) {
    Write-Host ("hwnd={0} rect=({1},{2})-({3},{4})" -f $w, $r.Left, $r.Top, $r.Right, $r.Bottom)
  }
}
$bmp.Dispose()
# full screen capture
Add-Type -AssemblyName System.Windows.Forms
$vs = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
Write-Host ("primary {0}x{1}" -f $vs.Width, $vs.Height)
$fs = New-Object System.Drawing.Bitmap($vs.Width, $vs.Height)
$g = [System.Drawing.Graphics]::FromImage($fs)
$g.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size($vs.Width, $vs.Height)))
$g.Dispose()
$fs.Save("$PSScriptRoot\full_screen.png", [System.Drawing.Imaging.ImageFormat]::Png)
$fs.Dispose()
Write-Host "full screen saved"
