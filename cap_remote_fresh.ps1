$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class PW5 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder s, int n);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$proc = Get-Process LDesk -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { Write-Output "NO LDESK"; exit 1 }
$targetPid = $proc.Id
$hwnd = [IntPtr]::Zero
$cb = { param($h2, $lp) $p=0; [PW5]::GetWindowThreadProcessId($h2, [ref]$p) | Out-Null; if ($p -eq $targetPid) { $l=[PW5]::GetWindowTextLength($h2); if ($l -gt 0) { $sb=New-Object System.Text.StringBuilder($l+1); [PW5]::GetWindowText($h2,$sb,$sb.Capacity) | Out-Null; if ($sb.ToString() -match 'Remote Desktop') { $script:hwnd=$h2; return $false } } }; return $true }
[PW5]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
Write-Output "pid=$targetPid remote hwnd=$hwnd"
if ($hwnd -eq [IntPtr]::Zero) { exit 1 }
$r = New-Object PW5+RECT
[PW5]::GetWindowRect($hwnd, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[PW5]::PrintWindow($hwnd, $hdc, 2) | Out-Null
$g.ReleaseHdc($hdc)
$g.Dispose()
$bmp.Save("J:\codex-work\LUODA-v3.0.1\remote_fresh.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "captured ${w}x${ht}"
