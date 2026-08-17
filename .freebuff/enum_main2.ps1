Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WinEnum2 {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern int GetClassNameW(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint procId);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
"@
$procs = [System.Diagnostics.Process]::GetProcessesByName("luoda")
$pidSet = @{}
foreach ($p in $procs) { $pidSet[$p.Id] = $true }
$cb = [WinEnum2+EnumProc]{
  param($h, $l)
  $title = New-Object System.Text.StringBuilder 256
  $cls = New-Object System.Text.StringBuilder 256
  [WinEnum2]::GetWindowTextW($h, $title, 256) | Out-Null
  [WinEnum2]::GetClassNameW($h, $cls, 256) | Out-Null
  $procId = 0
  [WinEnum2]::GetWindowThreadProcessId($h, [ref]$procId) | Out-Null
  if ($pidSet.ContainsKey($procId) -and $title.Length -gt 0) {
    Write-Output ("proc=$procId vis=" + [WinEnum2]::IsWindowVisible($h) + " cls=" + $cls.ToString() + " title=" + $title.ToString())
  }
  return $true
}
[WinEnum2]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
