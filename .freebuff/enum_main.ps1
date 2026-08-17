Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WinEnum {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern int GetClassNameW(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
"@
$proc = [System.Diagnostics.Process]::GetProcessesByName("luoda")
$pids = @{}
foreach ($p in $proc) { $pids[$p.Id] = $true }
$cb = [WinEnum+EnumProc]{
  param($h, $l)
  $title = New-Object System.Text.StringBuilder 256
  $cls = New-Object System.Text.StringBuilder 256
  [WinEnum]::GetWindowTextW($h, $title, 256) | Out-Null
  [WinEnum]::GetClassNameW($h, $cls, 256) | Out-Null
  $pid = 0
  [WinEnum]::GetWindowThreadProcessId($h, [ref]$pid) | Out-Null
  if ($pids.ContainsKey($pid) -and $title.Length -gt 0) {
    Write-Output ("pid=$pid vis=" + [WinEnum]::IsWindowVisible($h) + " cls=" + $cls.ToString() + " title=" + $title.ToString())
  }
  return $true
}
[WinEnum]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
