param([int]$CX=500, [int]$CY=700)
$ErrorActionPreference='Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Foc {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr i);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][Foc]::SetProcessDPIAware()
$targetPid = (Get-Process LDesk).Id
$script:mainHwnd=[IntPtr]::Zero; $script:r=$null
$cb=[Foc+EnumWindowsProc]{ param($hwnd,$lparam)
  $p=0; [Foc]::GetWindowThreadProcessId($hwnd,[ref]$p)|Out-Null
  if($p -eq $targetPid -and [Foc]::IsWindowVisible($hwnd)){
    $len=[Foc]::GetWindowTextLength($hwnd); $sb=New-Object System.Text.StringBuilder($len+1)
    [Foc]::GetWindowText($hwnd,$sb,$sb.Capacity)|Out-Null
    if($sb.ToString() -notmatch 'Remote Desktop'){ $rr=New-Object Foc+RECT; [Foc]::GetWindowRect($hwnd,[ref]$rr)|Out-Null; $script:mainHwnd=$hwnd; $script:r=$rr }
  }
  return $true
}
[Foc]::EnumWindows($cb,[IntPtr]::Zero)|Out-Null
$rect=$script:r
$mt=[Foc]::GetCurrentThreadId(); $tt=0; [Foc]::GetWindowThreadProcessId($script:mainHwnd,[ref]$tt)|Out-Null
$att=[Foc]::AttachThreadInput($mt,$tt,$true)
[Foc]::SetForegroundWindow($script:mainHwnd)|Out-Null
Start-Sleep -Milliseconds 400
if($att){[Foc]::AttachThreadInput($mt,$tt,$false)|Out-Null}
$sx=$rect.Left+$CX; $sy=$rect.Top+$CY
[Foc]::SetCursorPos($sx,$sy)|Out-Null
Start-Sleep -Milliseconds 150
[Foc]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [Foc]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 700
Write-Output "clicked window-local ($CX,$CY) -> screen ($sx,$sy)"
# screenshot
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class Cap2 {
  [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
  [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr hdc);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int w, int h);
  [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);
  [DllImport("gdi32.dll")] public static extern bool BitBlt(IntPtr hdc, int x, int y, int w, int h, IntPtr src, int sx, int sy, uint rop);
  [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr obj);
  [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr dc);
}
"@
$dc=[Cap2]::GetDC([IntPtr]::Zero); $cdc=[Cap2]::CreateCompatibleDC($dc)
$bmp=[Cap2]::CreateCompatibleBitmap($dc,($rect.Right-$rect.Left),($rect.Bottom-$rect.Top))
[Cap2]::SelectObject($cdc,$bmp)|Out-Null
[Cap2]::BitBlt($cdc,0,0,($rect.Right-$rect.Left),($rect.Bottom-$rect.Top),$dc,$rect.Left,$rect.Top,0x00CC0020)|Out-Null
$b=[System.Drawing.Image]::FromHbitmap($bmp)
$b.Save('J:\codex-work\LUODA-v3.0.1\focus_check.png',[System.Drawing.Imaging.ImageFormat]::Png)
[Cap2]::DeleteObject($bmp); [Cap2]::DeleteDC($cdc); [Cap2]::ReleaseDC([IntPtr]::Zero,$dc)
# scan for green border pixels (7,193,96) in y 600..875, x 430..1150
$bmp2=[System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\focus_check.png')
$minX=99999; $maxX=-1; $minY=99999; $maxY=-1; $count=0
for($y=600;$y -le 874;$y+=2){ for($x=430;$x -le 1150;$x+=2){
  $c=$bmp2.GetPixel($x,$y)
  if([Math]::Abs($c.R-7) -le 12 -and [Math]::Abs($c.G-193) -le 12 -and [Math]::Abs($c.B-96) -le 12){
    $count++
    if($x -lt $minX){$minX=$x}; if($x -gt $maxX){$maxX=$x}; if($y -lt $minY){$minY=$y}; if($y -gt $maxY){$maxY=$y}
  }
}}
Write-Output "GREEN PIXELS count=$count bbox=($minX,$minY)-($maxX,$maxY)"
$bmp2.Dispose()


