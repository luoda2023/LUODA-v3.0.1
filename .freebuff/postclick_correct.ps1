$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class PC {
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
$script:main = [IntPtr]::Zero
$cb = {
  param($h, $lp)
  $sb = New-Object System.Text.StringBuilder 128
  [PC]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTER_RUNNER_WIN32_WINDOW" -and [PC]::IsWindowVisible($h)) {
    $p = 0; [PC]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
    if ($p -eq 20180) { $script:main = $h; return $false }
  }
  return $true
}
[PC]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$script:fv = [IntPtr]::Zero
$cb2 = {
  param($h, $lp)
  $sb = New-Object System.Text.StringBuilder 128
  [PC]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTERVIEW") { $script:fv = $h; return $false }
  return $true
}
[PC]::EnumChildWindows($script:main, $cb2, [IntPtr]::Zero) | Out-Null
Write-Host ("main={0} fv={1}" -f $script:main, $script:fv)
# BT icon is at app-internal window-rel (350,83). FLUTTERVIEW client origin ≈ window origin + (6,1).
# So client coords on FLUTTERVIEW = (350-6, 83-1) = (344, 82).
$cx = 344; $cy = 82
Write-Host ("posting click at client ({0},{1})" -f $cx, $cy)
$lp = [IntPtr]((($cy -band 0xFFFF) -shl 16) -bor ($cx -band 0xFFFF))
[PC]::PostMessage($script:fv, 0x0201, [IntPtr]1, $lp) | Out-Null
Start-Sleep -Milliseconds 80
[PC]::PostMessage($script:fv, 0x0202, [IntPtr]0, $lp) | Out-Null
Start-Sleep -Milliseconds 2200
# also try a small grid around it in case of sub-pixel offset
foreach ($off in @(@(0,0), @(0,4), @(4,0), @(-4,0), @(0,-4))) {
  $gx = $cx + $off[0]; $gy = $cy + $off[1]
  $glp = [IntPtr]((($gy -band 0xFFFF) -shl 16) -bor ($gx -band 0xFFFF))
  [PC]::PostMessage($script:fv, 0x0201, [IntPtr]1, $glp) | Out-Null
  Start-Sleep -Milliseconds 50
  [PC]::PostMessage($script:fv, 0x0202, [IntPtr]0, $glp) | Out-Null
  Start-Sleep -Milliseconds 600
}
Start-Sleep -Milliseconds 1500
# capture for verification (window region + PW)
[PC]::ShowWindow($script:main, 9) | Out-Null
[PC]::SetForegroundWindow($script:main) | Out-Null
Start-Sleep -Milliseconds 600
$mr = New-Object PC+RECT
[PC]::GetWindowRect($script:main, [ref]$mr) | Out-Null
$w = $mr.Right - $mr.Left; $h = $mr.Bottom - $mr.Top
$scr = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($scr)
$g.CopyFromScreen($mr.Left, $mr.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
$g.Dispose()
$scr.Save("$PSScriptRoot\postclick_after.png", [System.Drawing.Imaging.ImageFormat]::Png)
$scr.Dispose()
Write-Host "captured postclick_after.png"
