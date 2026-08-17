$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class PW6 {
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
$found = @()
$cb = { param($h2, $lp) $p=0; [PW6]::GetWindowThreadProcessId($h2, [ref]$p) | Out-Null; if ($p -eq $targetPid) { $l=[PW6]::GetWindowTextLength($h2); if ($l -gt 0) { $sb=New-Object System.Text.StringBuilder($l+1); [PW6]::GetWindowText($h2,$sb,$sb.Capacity) | Out-Null; $script:found += @{hwnd=$h2; title=$sb.ToString()} } }; return $true }
[PW6]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$i = 0
foreach ($f in $found) {
  $i++
  $r = New-Object PW6+RECT
  [PW6]::GetWindowRect([IntPtr]$f.hwnd, [ref]$r) | Out-Null
  $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
  if ($w -le 0 -or $ht -le 0) { Write-Output "skip $($f.title)"; continue }
  $bmp = New-Object System.Drawing.Bitmap($w, $ht)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g.GetHdc()
  [PW6]::PrintWindow([IntPtr]$f.hwnd, $hdc, 2) | Out-Null
  $g.ReleaseHdc($hdc); $g.Dispose()
  $out = "J:\codex-work\LUODA-v3.0.1\ldesk_win_$i.png"
  $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output "win$i hwnd=$($f.hwnd) ${w}x${ht} title=$($f.title) -> $out"
}
