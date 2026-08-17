Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
public class WinCap3 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
  public struct RECT { public int Left, Top, Right, Bottom; }
  public static Bitmap Capture(IntPtr hwnd, uint flags) {
    RECT r; GetWindowRect(hwnd, out r);
    int w = r.Right - r.Left, h = r.Bottom - r.Top;
    if (w <= 0 || h <= 0) return null;
    Bitmap bmp = new Bitmap(w, h);
    using (Graphics g = Graphics.FromImage(bmp)) {
      IntPtr hdc = g.GetHdc();
      PrintWindow(hwnd, hdc, flags);
      g.ReleaseHdc(hdc);
    }
    return bmp;
  }
}
"@
foreach ($flags in @(0, 2)) {
  $bmp = [WinCap3]::Capture([IntPtr]198572, $flags)
  if ($bmp) {
    $bmp.Save("J:\codex-work\LUODA-v3.0.1\agent_memory\mstsc_pw_$flags.png", [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "captured flags=$flags $($bmp.Width)x$($bmp.Height)"
    $bmp.Dispose()
  } else { Write-Host "capture failed flags=$flags" }
}
