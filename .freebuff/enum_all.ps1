Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class Win2 {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
}
"@
$sb = New-Object System.Text.StringBuilder 512
$cl = New-Object System.Text.StringBuilder 256
$script:list = @()
$cb = {
  param($h, $lp)
  [Win2]::GetWindowText($h, $sb, 512) | Out-Null
  [Win2]::GetClassName($h, $cl, 256) | Out-Null
  $t = $sb.ToString(); $c = $cl.ToString()
  if ($t -ne "" -or $c -match "LDesk|Flutter|LDPlayer|Qt") {
    $pid2 = 0
    [Win2]::GetWindowThreadProcessId($h, [ref]$pid2) | Out-Null
    $script:list += ("hwnd={0} cls={1} title='{2}' pid={3} vis={4}" -f $h, $c, $t, $pid2, [Win2]::IsWindowVisible($h))
  }
  return $true
}
[Win2]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$script:list | ForEach-Object { Write-Host $_ }
