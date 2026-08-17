$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class SC {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
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
  [SC]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTER_RUNNER_WIN32_WINDOW" -and [SC]::IsWindowVisible($h)) {
    $p = 0; [SC]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
    if ($p -eq 20180) { $script:main = $h; return $false }
  }
  return $true
}
[SC]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$mr = New-Object SC+RECT
[SC]::GetWindowRect($script:main, [ref]$mr) | Out-Null
[SC]::ShowWindow($script:main, 9) | Out-Null
[SC]::SetForegroundWindow($script:main) | Out-Null
Start-Sleep -Milliseconds 400
$w = $mr.Right - $mr.Left; $h = $mr.Bottom - $mr.Top
$scr = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($scr)
$g.CopyFromScreen($mr.Left, $mr.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
$g.Dispose()
$scr.Save("$PSScriptRoot\sync_scr.png", [System.Drawing.Imaging.ImageFormat]::Png)
$scr.Dispose()
$pw = [SC]::CapturePW($script:main)
$pw.Save("$PSScriptRoot\sync_pw.png", [System.Drawing.Imaging.ImageFormat]::Png)
$pw.Dispose()
Write-Host ("window rect=({0},{1})-({2},{3}) size {4}x{5}" -f $mr.Left, $mr.Top, $mr.Right, $mr.Bottom, $w, $h)
Write-Host "saved sync_scr.png and sync_pw.png"
