$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class AB {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$script:main = [IntPtr]::Zero
$cb = {
  param($h, $lp)
  $sb = New-Object System.Text.StringBuilder 128
  [AB]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTER_RUNNER_WIN32_WINDOW" -and [AB]::IsWindowVisible($h)) {
    $p = 0; [AB]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
    if ($p -eq 20180) { $script:main = $h; return $false }
  }
  return $true
}
[AB]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
if ($script:main -eq [IntPtr]::Zero) { Write-Host "MAIN NOT FOUND"; exit 1 }
[AB]::ShowWindow($script:main, 9) | Out-Null
[AB]::SetForegroundWindow($script:main) | Out-Null
Start-Sleep -Milliseconds 700
$mr = New-Object AB+RECT
[AB]::GetWindowRect($script:main, [ref]$mr) | Out-Null
Write-Host ("win=({0},{1})-({2},{3}) fg={4}" -f $mr.Left, $mr.Top, $mr.Right, $mr.Bottom, ([AB]::GetForegroundWindow() -eq $script:main))
# capture window region
$w = $mr.Right - $mr.Left; $h = $mr.Bottom - $mr.Top
function TakeShot {
  $bmp = New-Object System.Drawing.Bitmap($w, $h)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($mr.Left, $mr.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
  $g.Dispose()
  return $bmp
}
function FindGreen($bmp, $y0, $y1) {
  $pts = New-Object System.Collections.ArrayList
  for ($y = $y0; $y -lt [Math]::Min($y1, $bmp.Height); $y++) {
    for ($x = 0; $x -lt $bmp.Width; $x++) {
      $c = $bmp.GetPixel($x, $y)
      if ($c.G -gt 150 -and $c.R -lt 80 -and $c.B -lt 130 -and ($c.G - $c.R) -gt 60 -and ($c.G - $c.B) -gt 50) {
        [void]$pts.Add(@($x, $y))
      }
    }
  }
  if ($pts.Count -lt 10) { return $null }
  $minX = 99999; $maxX = -1; $minY = 99999; $maxY = -1
  foreach ($p in $pts) {
    if ($p[0] -lt $minX) { $minX = $p[0] }; if ($p[0] -gt $maxX) { $maxX = $p[0] }
    if ($p[1] -lt $minY) { $minY = $p[1] }; if ($p[1] -gt $maxY) { $maxY = $p[1] }
  }
  return @{ cx = [int](($minX + $maxX) / 2); cy = [int](($minY + $maxY) / 2); n = $pts.Count }
}
# phase 1: find BT icon in search-row band (window-rel y 100-230; icon sits there after Qoder shift)
$bmp1 = TakeShot
$icon = FindGreen $bmp1 100 230
if (-not $icon) { $icon = FindGreen $bmp1 60 260 }
if (-not $icon) { Write-Host "NO GREEN ICON FOUND"; $bmp1.Save("$PSScriptRoot\atomic_noicon.png", [System.Drawing.Imaging.ImageFormat]::Png); exit 1 }
$sx = $mr.Left + $icon.cx; $sy = $mr.Top + $icon.cy
Write-Host ("green icon at winrel ({0},{1}) n={2} -> screen ({3},{4})" -f $icon.cx, $icon.cy, $icon.n, $sx, $sy)
$bmp1.Save("$PSScriptRoot\atomic_before.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp1.Dispose()
# phase 2: click
[AB]::SetCursorPos($sx, $sy) | Out-Null
Start-Sleep -Milliseconds 150
[AB]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 80
[AB]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 2200
# phase 3: verify
$bmp2 = TakeShot
$bmp2.Save("$PSScriptRoot\atomic_after.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g2 = FindGreen $bmp2 60 260
Write-Host ("after click green: {0}" -f ($(if ($g2) { "n=$($g2.n) at ($($g2.cx),$($g2.cy))" } else { "none" })))
$bmp2.Dispose()
Write-Host "done"
