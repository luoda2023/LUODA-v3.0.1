param([int]$CX, [int]$CY, [string]$Tag = "click")
$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class FS {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wp, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
}
"@
$script:main = [IntPtr]::Zero
$cb = {
  param($h, $lp)
  $sb = New-Object System.Text.StringBuilder 128
  [FS]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTER_RUNNER_WIN32_WINDOW" -and [FS]::IsWindowVisible($h)) {
    $p = 0; [FS]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
    if ($p -eq 20180) { $script:main = $h; return $false }
  }
  return $true
}
[FS]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$script:fv = [IntPtr]::Zero
$cb2 = {
  param($h, $lp)
  $sb = New-Object System.Text.StringBuilder 128
  [FS]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTERVIEW") { $script:fv = $h; return $false }
  return $true
}
[FS]::EnumChildWindows($script:main, $cb2, [IntPtr]::Zero) | Out-Null
[FS]::ShowWindow($script:main, 9) | Out-Null
[FS]::SetForegroundWindow($script:main) | Out-Null
Start-Sleep -Milliseconds 500
$lp = [IntPtr]((($CY -band 0xFFFF) -shl 16) -bor ($CX -band 0xFFFF))
# full sequence
[FS]::PostMessage($script:fv, 0x0200, [IntPtr]0, $lp) | Out-Null          # WM_MOUSEMOVE
Start-Sleep -Milliseconds 80
[FS]::PostMessage($script:fv, 0x0200, [IntPtr]1, $lp) | Out-Null          # WM_MOUSEMOVE w/ MK_LBUTTON
Start-Sleep -Milliseconds 80
[FS]::PostMessage($script:fv, 0x0201, [IntPtr]1, $lp) | Out-Null          # WM_LBUTTONDOWN
Start-Sleep -Milliseconds 120
[FS]::PostMessage($script:fv, 0x0202, [IntPtr]0, $lp) | Out-Null          # WM_LBUTTONUP
Start-Sleep -Milliseconds 2000
Write-Host "${Tag}: sent full mouse seq at client (${CX},${CY}) to fv=$($script:fv)"
