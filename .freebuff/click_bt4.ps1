$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class C4 {
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
  [C4]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTER_RUNNER_WIN32_WINDOW" -and [C4]::IsWindowVisible($h)) {
    $p = 0; [C4]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
    if ($p -eq 20180) { $script:main = $h; return $false }
  }
  return $true
}
[C4]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
[C4]::ShowWindow($script:main, 9) | Out-Null
[C4]::SetForegroundWindow($script:main) | Out-Null
Start-Sleep -Milliseconds 900
Write-Host ("fg={0} target={1} match={2}" -f [C4]::GetForegroundWindow(), $script:main, ([C4]::GetForegroundWindow() -eq $script:main))
$mr = New-Object C4+RECT
[C4]::GetWindowRect($script:main, [ref]$mr) | Out-Null
# click the bright green icon seen at screen ~(1054-1072, 184-210); pick center
$x = [int](($mr.Left + 1058))  # absolute mark
$x = 1063; $y = 191
[C4]::SetCursorPos($x, $y) | Out-Null
Start-Sleep -Milliseconds 250
[C4]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 100
[C4]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 2500
Write-Host "clicked ($x,$y)"
# real-screen capture of window region
$w = $mr.Right - $mr.Left; $h = $mr.Bottom - $mr.Top
$scr = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($scr)
$g.CopyFromScreen($mr.Left, $mr.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
$g.Dispose()
$scr.Save("$PSScriptRoot\scr_after4.png", [System.Drawing.Imaging.ImageFormat]::Png)
$scr.Dispose()
Write-Host "screen capture saved"
