param([int]$PidFilter = 0)
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class FO2 {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  public struct RECT { public int L, T, R, B; }
}
'@
$out = @()
[FO2]::EnumWindows({ param($h, $l)
  if ([FO2]::IsWindowVisible($h)) {
    $p = 0; [FO2]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
    if ($PidFilter -eq 0 -or $p -eq $PidFilter) {
      $sb = New-Object System.Text.StringBuilder 256
      [FO2]::GetClassName($h, $sb, 256) | Out-Null
      $tb = New-Object System.Text.StringBuilder 256
      [FO2]::GetWindowText($h, $tb, 256) | Out-Null
      $r = New-Object FO2+RECT
      [FO2]::GetWindowRect($h, [ref]$r) | Out-Null
      $ex = [FO2]::GetWindowLong($h, -20)
      $out += ("hwnd={0} pid={1} class={2} title={3} rect={4},{5},{6},{7} ex=0x{8:X}" -f $h, $p, $sb.ToString(), $tb.ToString(), $r.L, $r.T, $r.R, $r.B, $ex)
    }
  }
  return $true
}, [IntPtr]::Zero) | Out-Null
$out
