param([int]$TargetPid = 20180, [string]$Out = "J:\codex-work\LUODA-v3.0.1\screen_now.png")
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinFocus3 {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$hWnd = [IntPtr]::Zero
$callback = {
  param($h, $lp)
  $p = 0
  [WinFocus3]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
  if ([int]$p -eq $TargetPid -and [WinFocus3]::IsWindowVisible($h)) { $script:hWnd = $h; return $false }
  return $true
}
[WinFocus3]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
Write-Host "hWnd=$hWnd"
if ($hWnd -ne [IntPtr]::Zero) {
  [WinFocus3]::ShowWindow($hWnd, 9) | Out-Null   # SW_RESTORE
  [WinFocus3]::SetForegroundWindow($hWnd) | Out-Null
  Start-Sleep -Milliseconds 500
  [WinFocus3]::BringWindowToTop($hWnd) | Out-Null
  [WinFocus3]::SetForegroundWindow($hWnd) | Out-Null
  Start-Sleep -Milliseconds 600
  $r = New-Object WinFocus3+RECT
  [WinFocus3]::GetWindowRect($hWnd, [ref]$r) | Out-Null
  Write-Host "RECT=$($r.Left),$($r.Top),$($r.Right),$($r.Bottom)"
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
  $bmp = New-Object System.Drawing.Bitmap($w, $h)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
  $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Write-Host "captured to $Out"
}
