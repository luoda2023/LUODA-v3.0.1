param([int]$X = 466, [int]$Y = 107)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class PostClick {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
  public const uint WM_LBUTTONDOWN = 0x0201;
  public const uint WM_LBUTTONUP = 0x0202;
  public const int MK_LBUTTON = 0x0001;
}
"@
$lp = [IntPtr]::new(($Y -shl 16) -bor ($X -band 0xFFFF))
[PostClick]::PostMessage([IntPtr]::new(852860), [PostClick]::WM_LBUTTONDOWN, [IntPtr]::new([PostClick]::MK_LBUTTON), $lp) | Out-Null
Start-Sleep -Milliseconds 120
[PostClick]::PostMessage([IntPtr]::new(852860), [PostClick]::WM_LBUTTONUP, [IntPtr]::Zero, $lp) | Out-Null
Write-Host "posted click at client $X,$Y"
