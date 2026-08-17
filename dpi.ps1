Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DpiInfo {
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);
  public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr hWnd, ref POINT lpPoint);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);
}
"@
$dpi = [DpiInfo]::GetDpiForWindow([IntPtr]592070)
Write-Host "LDesk window DPI=$dpi (scale=$([math]::Round($dpi/96.0*100))%)"
$p = New-Object DpiInfo+POINT
$p.X = 1430; $p.Y = 588
$r = [DpiInfo]::ScreenToClient([IntPtr]592070, [ref]$p)
Write-Host "client coords of (1430,588): $($p.X),$($p.Y) success=$r"
