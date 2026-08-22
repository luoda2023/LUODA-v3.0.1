# E2E helper: screenshot the whole screen (or a window by title) to PNG, then
# OCR it with the Windows zh-CN engine. Usage:
#   powershell -File e2e_shot.ps1 <out.png> [windowTitle]
param(
  [Parameter(Mandatory=$true)][string]$OutPath,
  [string]$WindowTitle = ''
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
if ($WindowTitle -ne '') {
  Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Win32Cap {
  [DllImport("user32.dll")] public static extern IntPtr FindWindowW(string cls, string title);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@
  $h = [Win32Cap]::FindWindowW($null, $WindowTitle)
  if ($h -eq [IntPtr]::Zero) { Write-Output "WINDOW_NOT_FOUND: $WindowTitle"; exit 1 }
  $r = New-Object Win32Cap+RECT
  [Win32Cap]::GetWindowRect($h, [ref]$r) | Out-Null
  $bounds = New-Object System.Drawing.Rectangle($r.L, $r.T, ($r.R - $r.L), ($r.B - $r.T))
}

$bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$g.Dispose()
$bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "SAVED: $OutPath ($($bounds.Width)x$($bounds.Height))"
