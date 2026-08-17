$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class PP {
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
  [PP]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTER_RUNNER_WIN32_WINDOW" -and [PP]::IsWindowVisible($h)) {
    $p = 0; [PP]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
    if ($p -eq 20180) { $script:main = $h; return $false }
  }
  return $true
}
[PP]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$mr = New-Object PP+RECT
[PP]::GetWindowRect($script:main, [ref]$mr) | Out-Null
Write-Host ("win=({0},{1})-({2},{3})" -f $mr.Left, $mr.Top, $mr.Right, $mr.Bottom)
# real screen capture of window region
[PP]::ShowWindow($script:main, 9) | Out-Null
[PP]::SetForegroundWindow($script:main) | Out-Null
Start-Sleep -Milliseconds 600
$w = $mr.Right - $mr.Left; $h = $mr.Bottom - $mr.Top
$scr = New-Object System.Drawing.Bitmap($w, $h)
$g2 = [System.Drawing.Graphics]::FromImage($scr)
$g2.CopyFromScreen($mr.Left, $mr.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
$g2.Dispose()
$scr.Save("$PSScriptRoot\probe_screen.png", [System.Drawing.Imaging.ImageFormat]::Png)
$pw = [PP]::CapturePW($script:main)
$pw.Save("$PSScriptRoot\probe_pw.png", [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("screen {0}x{1}  pw {2}x{3}" -f $scr.Width, $scr.Height, $pw.Width, $pw.Height)
function DumpRow($bmp, $name, $y0) {
  $pts = @(430, 450, 470, 484, 490, 496, 502, 510, 520, 530)
  $s = "  $name y=${y0}: "
  foreach ($x in $pts) {
    if ($x -ge $bmp.Width) { continue }
    $c = $bmp.GetPixel($x, $y0)
    $s += ("x={0}({1},{2},{3}) " -f $x, $c.R, $c.G, $c.B)
  }
  Write-Host $s
}
foreach ($y0 in @(85, 90, 95, 100, 105, 110)) {
  DumpRow $pw "PW " $y0
  DumpRow $scr "SCR" $y0
}
# green scan on both, top 240
foreach ($pair in @(@($pw, "PW"), @($scr, "SCR"))) {
  $b = $pair[0]; $nm = $pair[1]
  $cnt = 0; $minX = 99999; $maxX = -1; $minY = 99999; $maxY = -1
  for ($y = 0; $y -lt [Math]::Min(240, $b.Height); $y++) {
    for ($x = 0; $x -lt $b.Width; $x++) {
      $c = $b.GetPixel($x, $y)
      if ($c.G -gt 90 -and $c.R -lt 60 -and $c.B -lt 90 -and ($c.G - $c.R) -gt 40 -and ($c.G - $c.B) -gt 25) {
        $cnt++
        if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
        if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
      }
    }
  }
  Write-Host ("  {0} green top240: {1} bbox x={2}-{3} y={4}-{5}" -f $nm, $cnt, $minX, $maxX, $minY, $maxY)
}
$pw.Dispose(); $scr.Dispose()
