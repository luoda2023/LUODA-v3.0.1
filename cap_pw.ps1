Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
public class WinCap {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  public struct RECT { public int Left, Top, Right, Bottom; }
  public static Bitmap Capture(IntPtr hwnd) {
    RECT r; GetWindowRect(hwnd, out r);
    int w = r.Right - r.Left, h = r.Bottom - r.Top;
    if (w <= 0 || h <= 0) return null;
    Bitmap bmp = new Bitmap(w, h);
    Graphics g = Graphics.FromImage(bmp);
    IntPtr hdc = g.GetHdc();
    PrintWindow(hwnd, hdc, 2); // PW_RENDERFULLCONTENT
    g.ReleaseHdc(hdc);
    g.Dispose();
    return bmp;
  }
}
"@
$bmp = [WinCap]::Capture([IntPtr]526418)
if ($bmp) { $bmp2 = New-Object System.Drawing.Bitmap(($bmp.Width * 2), ($bmp.Height * 2)); $g = [System.Drawing.Graphics]::FromImage($bmp2); $g.DrawImage($bmp, 0, 0, $bmp2.Width, $bmp2.Height); $bmp2.Save("J:\codex-work\LUODA-v3.0.1\agent_memory\remote_pw2x.png", [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp2.Dispose(); $bmp.Dispose(); Write-Host "captured $($bmp.Width)x$($bmp.Height)" } else { Write-Host "capture failed" }
