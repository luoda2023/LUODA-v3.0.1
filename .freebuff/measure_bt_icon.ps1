Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class Win {
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string name);
  [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string name);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lParam);
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  public struct RECT { public int L, T, R, B; }
  public struct POINT { public int X, Y; }
}
"@
$main = [Win]::FindWindow($null, "LDesk")
if ($main -eq [IntPtr]::Zero) { Write-Host "MAIN: not found"; exit 1 }
$mr = New-Object Win+RECT
[Win]::GetWindowRect($main, [ref]$mr) | Out-Null
Write-Host ("MAIN hwnd={0} rect=({1},{2})-({3},{4}) visible={5}" -f $main, $mr.L, $mr.T, $mr.R, $mr.B, [Win]::IsWindowVisible($main))
# enumerate all child windows of main
$children = @()
$proc = {
  param($h)
  $rect = New-Object Win+RECT
  [Win]::GetWindowRect($h, [ref]$rect) | Out-Null
  $clr = New-Object Win+RECT
  [Win]::GetClientRect($h, [ref]$clr) | Out-Null
  Write-Host ("  child hwnd={0} win=({1},{2})-({3},{4}) client={5}x{6} vis={7}" -f $h, $rect.L, $rect.T, $rect.R, $rect.B, $clr.R, $clr.B, [Win]::IsWindowVisible($h))
}
[Win]::EnumChildWindows($main, $proc, [IntPtr]::Zero) | Out-Null
Write-Host "---"
# find FLUTTERVIEW
$fv = [Win]::FindWindowEx($main, [IntPtr]::Zero, "FLUTTERVIEW", $null)
if ($fv -eq [IntPtr]::Zero) { $fv = [Win]::FindWindowEx($main, [IntPtr]::Zero, "FlutterView", $null) }
Write-Host ("FLUTTERVIEW hwnd={0}" -f $fv)
$cr = New-Object Win+RECT
[Win]::GetWindowRect($fv, [ref]$cr) | Out-Null
Write-Host ("  win rect=({0},{1})-({2},{3})" -f $cr.L, $cr.T, $cr.R, $cr.B)
# bring to front for capture
[Win]::ShowWindow($main, 9) | Out-Null   # SW_RESTORE
[Win]::SetForegroundWindow($main) | Out-Null
Start-Sleep -Milliseconds 400
# capture window region
$w = $mr.R - $mr.L; $h = $mr.B - $mr.T
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($mr.L, $mr.T, 0, 0, (New-Object System.Drawing.Size($w, $h)))
# find green (#107C41-ish) pixels in top 160px
$targets = @()
for ($y = 0; $y -lt [Math]::Min(160, $h); $y += 1) {
  for ($x = 0; $x -lt $w; $x += 1) {
    $c = $bmp.GetPixel($x, $y)
    if ($c.G -gt 90 -and $c.R -lt 60 -and $c.B -lt 90 -and ($c.G - $c.R) -gt 40 -and ($c.G - $c.B) -gt 25) {
      $targets += ,@($x, $y)
    }
  }
}
Write-Host ("green pixels found: {0}" -f $targets.Count)
if ($targets.Count -gt 0) {
  $minX = ($targets | ForEach-Object { $_[0] } | Measure-Object -Minimum).Minimum
  $maxX = ($targets | ForEach-Object { $_[0] } | Measure-Object -Maximum).Maximum
  $minY = ($targets | ForEach-Object { $_[1] } | Measure-Object -Minimum).Minimum
  $maxY = ($targets | ForEach-Object { $_[1] } | Measure-Object -Maximum).Maximum
  Write-Host ("  bbox: x={0}-{1} y={2}-{3} (window-relative)" -f $minX, $maxX, $minY, $maxY)
  $cx = [int](($minX + $maxX) / 2); $cy = [int](($minY + $maxY) / 2)
  Write-Host ("  center: ({0},{1}) window-relative" -f $cx, $cy)
  # FLUTTERVIEW-relative = window-relative - (fv.L - main.L, fv.T - main.T)
  $ox = $cr.L - $mr.L; $oy = $cr.T - $mr.T
  Write-Host ("  FLUTTERVIEW offset=({0},{1}) -> client click=({2},{3})" -f $ox, $oy, ($cx - $ox), ($cy - $oy))
  Write-Host ("  screen click=({0},{1})" -f ($mr.L + $cx), ($mr.T + $cy))
}
$bmp.Save("$PSScriptRoot\bt_measure.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
