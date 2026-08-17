Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class RT {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wp, IntPtr lp, uint flags, uint timeout, out IntPtr result);
  [DllImport("user32.dll")] public static extern bool IsHungAppWindow(IntPtr h);
}
"@
$script:main = [IntPtr]::Zero
$cb = {
  param($h, $lp)
  $sb = New-Object System.Text.StringBuilder 128
  [RT]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTER_RUNNER_WIN32_WINDOW" -and [RT]::IsWindowVisible($h)) {
    $p = 0; [RT]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
    if ($p -eq 20180) { $script:main = $h; return $false }
  }
  return $true
}
[RT]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$script:fv = [IntPtr]::Zero
$cb2 = {
  param($h, $lp)
  $sb = New-Object System.Text.StringBuilder 128
  [RT]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq "FLUTTERVIEW") { $script:fv = $h; return $false }
  return $true
}
[RT]::EnumChildWindows($script:main, $cb2, [IntPtr]::Zero) | Out-Null
$r = [IntPtr]::Zero
$t1 = [Diagnostics.Stopwatch]::StartNew()
$res = [RT]::SendMessageTimeout($script:fv, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero, 0x0002, 3000, [ref]$r)  # WM_NULL, SMTO_ABORTIFHUNG
$t1.Stop()
Write-Host ("main hwnd={0} fv={1} hung={2}" -f $script:main, $script:fv, [RT]::IsHungAppWindow($script:fv))
Write-Host ("WM_NULL to FV: result={0} took={1}ms" -f $res, $t1.ElapsedMilliseconds)
$r2 = [IntPtr]::Zero
$t2 = [Diagnostics.Stopwatch]::StartNew()
$res2 = [RT]::SendMessageTimeout($script:main, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero, 0x0002, 3000, [ref]$r2)
$t2.Stop()
Write-Host ("WM_NULL to MAIN: result={0} took={1}ms" -f $res2, $t2.ElapsedMilliseconds)
