Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class Win3 {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  public struct RECT { public int L, T, R, B; }
}
"@
$script:main = [IntPtr]::Zero
$cb = {
  param($h, $lp)
  $sb = New-Object System.Text.StringBuilder 128
  [Win3]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTER_RUNNER_WIN32_WINDOW" -and [Win3]::IsWindowVisible($h)) {
    $p = 0; [Win3]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
    if ($p -eq 20180) { $script:main = $h; return $false }
  }
  return $true
}
[Win3]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
if ($script:main -eq [IntPtr]::Zero) { Write-Host "MAIN: not found"; exit 1 }
$mr = New-Object Win3+RECT
[Win3]::GetWindowRect($script:main, [ref]$mr) | Out-Null
Write-Host ("MAIN hwnd={0} rect=({1},{2})-({3},{4})" -f $script:main, $mr.L, $mr.T, $mr.R, $mr.B)
# FLUTTERVIEW child
$script:fv = [IntPtr]::Zero
$cb2 = {
  param($h, $lp)
  $sb = New-Object System.Text.StringBuilder 128
  [Win3]::GetClassName($h, $sb, 128) | Out-Null
  $c = $sb.ToString()
  if ($c -eq "FLUTTERVIEW" -or $c -eq "FlutterView") { $script:fv = $h; return $false }
  return $true
}
[Win3]::EnumChildWindows($script:main, $cb2, [IntPtr]::Zero) | Out-Null
Write-Host ("FLUTTERVIEW hwnd={0}" -f $script:fv)
$fr = New-Object Win3+RECT
if ($script:fv -ne [IntPtr]::Zero) { [Win3]::GetWindowRect($script:fv, [ref]$fr) | Out-Null } else { $fr = $mr }
Write-Host ("  FV rect=({0},{1})-({2},{3})" -f $fr.L, $fr.T, $fr.R, $fr.B)
[Win3]::ShowWindow($script:main, 9) | Out-Null
[Win3]::SetForegroundWindow($script:main) | Out-Null
Start-Sleep -Milliseconds 500
$w = $mr.R - $mr.L; $h = $mr.B - $mr.T
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($mr.L, $mr.T, 0, 0, (New-Object System.Drawing.Size($w, $h)))
$targets = New-Object System.Collections.ArrayList
for ($y = 0; $y -lt [Math]::Min(220, $h); $y += 1) {
  for ($x = 0; $x -lt $w; $x += 1) {
    $c = $bmp.GetPixel($x, $y)
    if ($c.G -gt 90 -and $c.R -lt 60 -and $c.B -lt 90 -and ($c.G - $c.R) -gt 40 -and ($c.G - $c.B) -gt 25) {
      [void]$targets.Add(@($x, $y))
    }
  }
}
Write-Host ("green pixels: {0}" -f $targets.Count)
if ($targets.Count -gt 0) {
  $minX = 99999; $maxX = -1; $minY = 99999; $maxY = -1
  foreach ($t in $targets) {
    if ($t[0] -lt $minX) { $minX = $t[0] }
    if ($t[0] -gt $maxX) { $maxX = $t[0] }
    if ($t[1] -lt $minY) { $minY = $t[1] }
    if ($t[1] -gt $maxY) { $maxY = $t[1] }
  }
  Write-Host ("  bbox x={0}-{1} y={2}-{3} (window-rel)" -f $minX, $maxX, $minY, $maxY)
  $cx = [int](($minX + $maxX) / 2); $cy = [int](($minY + $maxY) / 2)
  Write-Host ("  center=({0},{1})  screen=({2},{3})" -f $cx, $cy, ($mr.L + $cx), ($mr.T + $cy))
  if ($script:fv -ne [IntPtr]::Zero) {
    $ox = $fr.L - $mr.L; $oy = $fr.T - $mr.T
    Write-Host ("  FV offset=({0},{1})  client click=({2},{3})" -f $ox, $oy, ($cx - $ox), ($cy - $oy))
  }
}
$bmp.Save("$PSScriptRoot\bt_measure2.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "saved bt_measure2.png"
