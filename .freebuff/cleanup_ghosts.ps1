Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Ghost {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  public struct RECT { public int L, T, R, B; }
  public static string[] ListOverlapping(int x1, int y1, int x2, int y2, int[] keepPids) {
    System.Collections.Generic.List<string> out_ = new System.Collections.Generic.List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      if (!IsWindowVisible(h)) return true;
      RECT r; GetWindowRect(h, out r);
      bool ov = r.L < x2 && r.R > x1 && r.T < y2 && r.B > y1;
      if (!ov) return true;
      uint pid; GetWindowThreadProcessId(h, out pid);
      bool keep = false;
      foreach (int k in keepPids) if ((int)pid == k) { keep = true; break; }
      StringBuilder sb = new StringBuilder(200);
      GetWindowText(h, sb, 200);
      bool alive = true;
      try { System.Diagnostics.Process.GetProcessById((int)pid); } catch { alive = false; }
      out_.Add(string.Format("hwnd=0x{0:X} pid={1} alive={2} keep={3} rect={4},{5}-{6},{7} title='{8}'",
        h.ToInt64(), pid, alive, keep, r.L, r.T, r.R, r.B, sb.ToString()));
      return true;
    }, IntPtr.Zero);
    return out_.ToArray();
  }
  public static bool CloseWindow(IntPtr h) {
    return PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); // WM_CLOSE
  }
}
'@
# LUODA window rect
$p = Get-Process luoda -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Write-Output "NO_LUODA"; exit 1 }
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class GR { 
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  public struct R { public int L,T,R2,B; }
}
'@
$r = New-Object GR+R
[GR]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
Write-Output "LUODA rect: $($r.L),$($r.T)-$($r.R2),$($r.B)"
$keep = @(1468, 10580, $p.Id)  # Freebuff, shell(10580), LUODA itself
$list = [Ghost]::ListOverlapping($r.L, $r.T, $r.R2, $r.B, $keep)
foreach ($w in $list) { Write-Output $w }
Write-Output "---"
# Close ghost windows (process not alive and not system)
foreach ($w in $list) {
  if ($w -match 'hwnd=(0x[0-9A-F]+) pid=(\d+) alive=(\w+) keep=(\w+)') {
    $hwnd = [Int64]$matches[1]; $pidS = [int]$matches[2]
    $alive = $matches[3] -eq 'True'; $keepF = $matches[4] -eq 'True'
    if (-not $keepF -and (-not $alive)) {
      Write-Output "Closing ghost hwnd=0x$($hwnd.ToString('X')) pid=$pidS"
      [Ghost]::CloseWindow([IntPtr]$hwnd) | Out-Null
    }
  }
}
Write-Output "done"
