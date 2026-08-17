param([int]$CX=500, [int]$CY=710)
$ErrorActionPreference='Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class CT {
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
[void][CT]::SetProcessDPIAware()
$targetPid = (Get-Process LDesk).Id
$script:mainHwnd=[IntPtr]::Zero; $script:r=$null
$cb=[CT+EnumWindowsProc]{ param($hwnd,$lparam)
  $p=0; [CT]::GetWindowThreadProcessId($hwnd,[ref]$p)|Out-Null
  if($p -eq $targetPid -and [CT]::IsWindowVisible($hwnd)){
    $len=[CT]::GetWindowTextLength($hwnd); $sb=New-Object System.Text.StringBuilder($len+1)
    [CT]::GetWindowText($hwnd,$sb,$sb.Capacity)|Out-Null
    if($sb.ToString() -notmatch 'Remote Desktop'){ $rr=New-Object CT+RECT; [CT]::GetWindowRect($hwnd,[ref]$rr)|Out-Null; $script:mainHwnd=$hwnd; $script:r=$rr }
  }
  return $true
}
[CT]::EnumWindows($cb,[IntPtr]::Zero)|Out-Null
$rect=$script:r
$mt=[CT]::GetCurrentThreadId(); $tt=0; [CT]::GetWindowThreadProcessId($script:mainHwnd,[ref]$tt)|Out-Null
$att=[CT]::AttachThreadInput($mt,$tt,$true)
[CT]::SetForegroundWindow($script:mainHwnd)|Out-Null
Start-Sleep -Milliseconds 400
if($att){[CT]::AttachThreadInput($mt,$tt,$false)|Out-Null}
$sx=$rect.Left+$CX; $sy=$rect.Top+$CY
[CT]::SetCursorPos($sx,$sy)|Out-Null
Start-Sleep -Milliseconds 150
[CT]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [CT]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 120
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class CapT {
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
$dc=[CapT]::GetDC([IntPtr]::Zero); $cdc=[CapT]::CreateCompatibleDC($dc)
$bmp=[CapT]::CreateCompatibleBitmap($dc,620,150)
[CapT]::SelectObject($cdc,$bmp)|Out-Null
[CapT]::BitBlt($cdc,0,0,620,150,$dc,$rect.Left+430,$rect.Top+620,0x00CC0020)|Out-Null
$b=[System.Drawing.Image]::FromHbitmap($bmp)
$b.Save('J:\codex-work\LUODA-v3.0.1\caret_check.png',[System.Drawing.Imaging.ImageFormat]::Png)
$b.Dispose()
[CapT]::DeleteObject($bmp); [CapT]::DeleteDC($cdc); [CapT]::ReleaseDC([IntPtr]::Zero,$dc)
Write-Output "clicked ($sx,$sy), captured caret_check"
