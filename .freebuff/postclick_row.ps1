$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class PR {
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
  [PR]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTER_RUNNER_WIN32_WINDOW" -and [PR]::IsWindowVisible($h)) {
    $p = 0; [PR]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
    if ($p -eq 20180) { $script:main = $h; return $false }
  }
  return $true
}
[PR]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$script:fv = [IntPtr]::Zero
$cb2 = {
  param($h, $lp)
  $sb = New-Object System.Text.StringBuilder 128
  [PR]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTERVIEW") { $script:fv = $h; return $false }
  return $true
}
[PR]::EnumChildWindows($script:main, $cb2, [IntPtr]::Zero) | Out-Null
# OPPO row at app-internal window-rel (170, 617) -> client (164, 616)
$cx = 164; $cy = 616
$lp = [IntPtr]((($cy -band 0xFFFF) -shl 16) -bor ($cx -band 0xFFFF))
Write-Host ("clicking OPPO row at client ({0},{1})" -f $cx, $cy)
[PR]::PostMessage($script:fv, 0x0201, [IntPtr]1, $lp) | Out-Null
Start-Sleep -Milliseconds 80
[PR]::PostMessage($script:fv, 0x0202, [IntPtr]0, $lp) | Out-Null
Start-Sleep -Milliseconds 1800
[PR]::ShowWindow($script:main, 9) | Out-Null
[PR]::SetForegroundWindow($script:main) | Out-Null
Start-Sleep -Milliseconds 500
$mr = New-Object PR+RECT
[PR]::GetWindowRect($script:main, [ref]$mr) | Out-Null
$w = $mr.Right - $mr.Left; $h = $mr.Bottom - $mr.Top
$scr = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($scr)
$g.CopyFromScreen($mr.Left, $mr.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
$g.Dispose()
$scr.Save("$PSScriptRoot\rowclick_after.png", [System.Drawing.Imaging.ImageFormat]::Png)
$scr.Dispose()
Write-Host "captured rowclick_after.png"
