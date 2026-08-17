$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class GCap {
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
  [GCap]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTER_RUNNER_WIN32_WINDOW" -and [GCap]::IsWindowVisible($h)) {
    $p = 0; [GCap]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
    if ($p -eq 20180) { $script:main = $h; return $false }
  }
  return $true
}
[GCap]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$bmp = [GCap]::CapturePW($script:main)
# collect green pixels in top 200 rows (both dark theme green #107C41 and bright green)
$pts = New-Object System.Collections.ArrayList
for ($y = 0; $y -lt [Math]::Min(200, $bmp.Height); $y++) {
  for ($x = 0; $x -lt $bmp.Width; $x++) {
    $c = $bmp.GetPixel($x, $y)
    $isGreen = ($c.G -gt 90 -and $c.R -lt 90 -and ($c.G - $c.R) -gt 40 -and ($c.G - $c.B) -gt 20)
    if ($isGreen) { [void]$pts.Add(@($x, $y)) }
  }
}
Write-Host ("total green: {0}" -f $pts.Count)
# simple clustering: sort by x, then group
$clusters = New-Object System.Collections.ArrayList
foreach ($p in $pts) {
  $added = $false
  foreach ($cl in $clusters) {
    if ([Math]::Abs($p[0] - $cl.cx) -lt 30 -and [Math]::Abs($p[1] - $cl.cy) -lt 25) {
      $cl.n++
      $cl.sx = [Math]::Min($cl.sx, $p[0]); $cl.ex = [Math]::Max($cl.ex, $p[0])
      $cl.sy = [Math]::Min($cl.sy, $p[1]); $cl.ey = [Math]::Max($cl.ey, $p[1])
      $cl.cx = [int](($cl.sx + $cl.ex) / 2); $cl.cy = [int](($cl.sy + $cl.ey) / 2)
      $added = $true
      break
    }
  }
  if (-not $added) {
    $cl = [PSCustomObject]@{ n = 1; sx = $p[0]; ex = $p[0]; sy = $p[1]; ey = $p[1]; cx = $p[0]; cy = $p[1] }
    [void]$clusters.Add($cl)
  }
}
$clusters | Sort-Object { $_.n } -Descending | ForEach-Object {
  Write-Host ("cluster n={0} x={1}-{2} y={3}-{4} center=({5},{6})" -f $_.n, $_.sx, $_.ex, $_.sy, $_.ey, $_.cx, $_.cy)
}
$bmp.Dispose()
