$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class CB {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wp, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
# find main window + FLUTTERVIEW
$script:main = [IntPtr]::Zero
$cb = {
  param($h, $lp)
  $sb = New-Object System.Text.StringBuilder 128
  [CB]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTER_RUNNER_WIN32_WINDOW" -and [CB]::IsWindowVisible($h)) {
    $p = 0; [CB]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
    if ($p -eq 20180) { $script:main = $h; return $false }
  }
  return $true
}
[CB]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$script:fv = [IntPtr]::Zero
$cb2 = {
  param($h, $lp)
  $sb = New-Object System.Text.StringBuilder 128
  [CB]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTERVIEW") { $script:fv = $h; return $false }
  return $true
}
[CB]::EnumChildWindows($script:main, $cb2, [IntPtr]::Zero) | Out-Null
Write-Host ("main={0} fv={1}" -f $script:main, $script:fv)
$fr = New-Object CB+RECT
[CB]::GetWindowRect($script:fv, [ref]$fr) | Out-Null
$mr = New-Object CB+RECT
[CB]::GetWindowRect($script:main, [ref]$mr) | Out-Null
# click at window-rel (493,102) -> FLUTTERVIEW client coords
$cx = 493 - ($fr.Left - $mr.Left)
$cy = 102 - ($fr.Top - $mr.Top)
Write-Host ("clicking client ({0},{1}) on FV hwnd={2}" -f $cx, $cy, $script:fv)
$lp = [IntPtr]((($cy -band 0xFFFF) -shl 16) -bor ($cx -band 0xFFFF))
[CB]::PostMessage($script:fv, 0x0201, [IntPtr]1, $lp) | Out-Null  # WM_LBUTTONDOWN
Start-Sleep -Milliseconds 60
[CB]::PostMessage($script:fv, 0x0202, [IntPtr]0, $lp) | Out-Null  # WM_LBUTTONUP
Start-Sleep -Milliseconds 1800
# capture real screen of window region
[CB]::ShowWindow($script:main, 9) | Out-Null
[CB]::SetForegroundWindow($script:main) | Out-Null
Start-Sleep -Milliseconds 500
$w = $mr.Right - $mr.Left; $h = $mr.Bottom - $mr.Top
$scr = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($scr)
$g.CopyFromScreen($mr.Left, $mr.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
$g.Dispose()
$scr.Save("$PSScriptRoot\after_click.png", [System.Drawing.Imaging.ImageFormat]::Png)
# analyze: green (bright) and orange pixels in top 200 rows; also dump AppBar strip rows
$green = 0; $orange = 0
$gminX = 99999; $gmaxX = -1; $gminY = 99999; $gmaxY = -1
$ominX = 99999; $omaxX = -1; $ominY = 99999; $omaxY = -1
for ($y = 0; $y -lt [Math]::Min(200, $h); $y++) {
  for ($x = 0; $x -lt $w; $x++) {
    $c = $scr.GetPixel($x, $y)
    if ($c.G -gt 150 -and $c.R -lt 80 -and $c.B -lt 130 -and ($c.G - $c.R) -gt 60) {
      $green++
      if ($x -lt $gminX) { $gminX = $x }; if ($x -gt $gmaxX) { $gmaxX = $x }
      if ($y -lt $gminY) { $gminY = $y }; if ($y -gt $gmaxY) { $gmaxY = $y }
    }
    elseif ($c.R -gt 200 -and $c.G -gt 100 -and $c.G -lt 200 -and $c.B -lt 80) {
      $orange++
      if ($x -lt $ominX) { $ominX = $x }; if ($x -gt $omaxX) { $omaxX = $x }
      if ($y -lt $ominY) { $ominY = $y }; if ($y -gt $omaxY) { $omaxY = $y }
    }
  }
}
Write-Host ("green top200: {0} bbox x={1}-{2} y={3}-{4}" -f $green, $gminX, $gmaxX, $gminY, $gmaxY)
Write-Host ("orange top200: {0} bbox x={1}-{2} y={3}-{4}" -f $orange, $ominX, $omaxX, $ominY, $omaxY)
$scr.Dispose()
