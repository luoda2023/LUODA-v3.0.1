Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinFix {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  public struct RECT { public int L, T, R, B; }
}
'@
$pids = @(Get-Process luoda -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
foreach ($pid0 in $pids) {
  [WinFix]::EnumWindows({ param($h, $l)
    $wp = 0
    [WinFix]::GetWindowThreadProcessId($h, [ref]$wp) | Out-Null
    if ($wp -eq $pid0 -and [WinFix]::IsWindowVisible($h)) {
      $r = New-Object WinFix+RECT
      [WinFix]::GetWindowRect($h, [ref]$r) | Out-Null
      $w = $r.R - $r.L; $hh = $r.B - $r.T
      if ($w -gt 600 -and $hh -gt 500) {
        [WinFix]::ShowWindow($h, 9) | Out-Null
        [WinFix]::SetWindowPos($h, [IntPtr]::Zero, 150, 60, $w, $hh, 0x0040 -bor 0x0004) | Out-Null  # SHOWWINDOW | NOZORDER
        [WinFix]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0040) | Out-Null  # TOPMOST
        $t = New-Object System.Text.StringBuilder 256
        [WinFix]::GetWindowText($h, $t, 256) | Out-Null
        Write-Output "restored hwnd=$h size=${w}x${hh} title=$($t.ToString())"
      }
    }
    return $true
  }, [IntPtr]::Zero) | Out-Null
}
