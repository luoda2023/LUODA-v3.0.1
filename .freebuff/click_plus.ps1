$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class CP {
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
  [CP]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTER_RUNNER_WIN32_WINDOW" -and [CP]::IsWindowVisible($h)) {
    $p = 0; [CP]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
    if ($p -eq 20180) { $script:main = $h; return $false }
  }
  return $true
}
[CP]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
[CP]::ShowWindow($script:main, 9) | Out-Null
[CP]::SetForegroundWindow($script:main) | Out-Null
Start-Sleep -Milliseconds 600
# the + button: app-internal ~(395,80) -> real screen (712+395, 111+80) = (1107, 191)
# But verify against live capture: find bright-green BT icon (app 350,83 -> screen (1062,194)); the + is ~45px right
$x = 1107; $y = 191
[CP]::SetCursorPos($x, $y) | Out-Null
Start-Sleep -Milliseconds 200
[CP]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 100
[CP]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 2500
Write-Host "clicked plus at ($x,$y)"
$mr = New-Object CP+RECT
[CP]::GetWindowRect($script:main, [ref]$mr) | Out-Null
$w = $mr.Right - $mr.Left; $h = $mr.Bottom - $mr.Top
$scr = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($scr)
$g.CopyFromScreen($mr.Left, $mr.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
$g.Dispose()
$scr.Save("$PSScriptRoot\plus_after.png", [System.Drawing.Imaging.ImageFormat]::Png)
$scr.Dispose()
Write-Host "captured plus_after.png"
