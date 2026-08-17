$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class MQ {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$script:wins = @()
$cb = {
  param($h, $lp)
  $t = New-Object System.Text.StringBuilder 512
  $c = New-Object System.Text.StringBuilder 128
  [MQ]::GetWindowText($h, $t, 512) | Out-Null
  [MQ]::GetClassName($h, $c, 128) | Out-Null
  $title = $t.ToString(); $cls = $c.ToString()
  if ($title -ne "" -and [MQ]::IsWindowVisible($h)) {
    $script:wins += ,@($h, $title, $cls)
  }
  return $true
}
[MQ]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
foreach ($w in $script:wins) {
  Write-Host ("hwnd={0} title='{1}' cls={2}" -f $w[0], $w[1], $w[2])
}
