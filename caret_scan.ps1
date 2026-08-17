param([int]$CX=470, [int]$CY=710)
$ErrorActionPreference='Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class CK {
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
[void][CK]::SetProcessDPIAware()
$targetPid = (Get-Process LDesk).Id
$script:mainHwnd=[IntPtr]::Zero; $script:r=$null
$cb=[CK+EnumWindowsProc]{ param($hwnd,$lparam)
  $p=0; [CK]::GetWindowThreadProcessId($hwnd,[ref]$p)|Out-Null
  if($p -eq $targetPid -and [CK]::IsWindowVisible($hwnd)){
    $len=[CK]::GetWindowTextLength($hwnd); $sb=New-Object System.Text.StringBuilder($len+1)
    [CK]::GetWindowText($hwnd,$sb,$sb.Capacity)|Out-Null
    if($sb.ToString() -notmatch 'Remote Desktop'){ $rr=New-Object CK+RECT; [CK]::GetWindowRect($hwnd,[ref]$rr)|Out-Null; $script:mainHwnd=$hwnd; $script:r=$rr }
  }
  return $true
}
[CK]::EnumWindows($cb,[IntPtr]::Zero)|Out-Null
$rect=$script:r
$mt=[CK]::GetCurrentThreadId(); $tt=0; [CK]::GetWindowThreadProcessId($script:mainHwnd,[ref]$tt)|Out-Null
$att=[CK]::AttachThreadInput($mt,$tt,$true)
[CK]::SetForegroundWindow($script:mainHwnd)|Out-Null
Start-Sleep -Milliseconds 400
if($att){[CK]::AttachThreadInput($mt,$tt,$false)|Out-Null}
$sx=$rect.Left+$CX; $sy=$rect.Top+$CY
[CK]::SetCursorPos($sx,$sy)|Out-Null
Start-Sleep -Milliseconds 150
[CK]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [CK]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 120
# capture 3x zoom region x 430..620, y 680..740
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class CapC {
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
$dc=[CapC]::GetDC([IntPtr]::Zero); $cdc=[CapC]::CreateCompatibleDC($dc)
$bmp=[CapC]::CreateCompatibleBitmap($dc,570,180)
[CapC]::SelectObject($cdc,$bmp)|Out-Null
[CapC]::BitBlt($cdc,0,0,570,180,$dc,$rect.Left+430,$rect.Top+680,0x00CC0020)|Out-Null
$b=[System.Drawing.Image]::FromHbitmap($bmp)
$b.Save('J:\codex-work\LUODA-v3.0.1\caret2.png',[System.Drawing.Imaging.ImageFormat]::Png)
$b.Dispose()
[CapC]::DeleteObject($bmp); [CapC]::DeleteDC($cdc); [CapC]::ReleaseDC([IntPtr]::Zero,$dc)
# scan for dark vertical caret pixels in x 430..1000 (window-local), y 690..740
$img2=[System.Drawing.Image]::FromFile('J:\codex-work\LUODA-v3.0.1\caret2.png')
for ($y=700; $y -le 740; $y+=1) {
  $line=''
  for ($x=0; $x -le 569; $x+=1) {
    $c=$img2.GetPixel($x,$y-680)
    if ($c.R -lt 100 -and $c.G -lt 100 -and $c.B -lt 100) { $line += '#' } else { $line += '.' }
  }
  $hasDark = $line -match '#{2,}'
  if ($hasDark) { Write-Output ("y=${y}: $line") }
}
$img2.Dispose()
Write-Output "clicked ($sx,$sy)"

