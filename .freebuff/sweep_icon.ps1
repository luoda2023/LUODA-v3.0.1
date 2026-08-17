Add-Type @"
using System;
using System.Runtime.InteropServices;
public class SweepClick {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
  public const uint WM_LBUTTONDOWN = 0x0201;
  public const uint WM_LBUTTONUP = 0x0202;
  public const int MK_LBUTTON = 0x0001;
}
"@
$points = @(@(487,104), @(470,104), @(500,104), @(487,92), @(487,118), @(505,118), @(455,104))
foreach ($pt in $points) {
  $x = $pt[0]; $y = $pt[1]
  $lp = [IntPtr]::new(($y -shl 16) -bor ($x -band 0xFFFF))
  [SweepClick]::PostMessage([IntPtr]::new(852860), [SweepClick]::WM_LBUTTONDOWN, [IntPtr]::new([SweepClick]::MK_LBUTTON), $lp) | Out-Null
  Start-Sleep -Milliseconds 100
  [SweepClick]::PostMessage([IntPtr]::new(852860), [SweepClick]::WM_LBUTTONUP, [IntPtr]::Zero, $lp) | Out-Null
  Start-Sleep -Milliseconds 900
  # capture left pane region and check for BT markers
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  $bmp = New-Object System.Drawing.Bitmap(480, 300)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen(576, 90, 0, 0, (New-Object System.Drawing.Size(480, 300)))
  $bmp.Save("J:\codex-work\LUODA-v3.0.1\.freebuff\sweep.png", [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Write-Host ("clicked client $x,$y")
}
