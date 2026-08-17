param([int]$CX=465, [int]$CY=650, [string]$Text='ABC123')
$ErrorActionPreference='Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class FK {
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
[void][FK]::SetProcessDPIAware()
$targetPid = (Get-Process LDesk).Id
$script:mainHwnd=[IntPtr]::Zero; $script:r=$null
$cb=[FK+EnumWindowsProc]{ param($hwnd,$lparam)
  $p=0; [FK]::GetWindowThreadProcessId($hwnd,[ref]$p)|Out-Null
  if($p -eq $targetPid -and [FK]::IsWindowVisible($hwnd)){
    $len=[FK]::GetWindowTextLength($hwnd); $sb=New-Object System.Text.StringBuilder($len+1)
    [FK]::GetWindowText($hwnd,$sb,$sb.Capacity)|Out-Null
    if($sb.ToString() -notmatch 'Remote Desktop'){ $rr=New-Object FK+RECT; [FK]::GetWindowRect($hwnd,[ref]$rr)|Out-Null; $script:mainHwnd=$hwnd; $script:r=$rr }
  }
  return $true
}
[FK]::EnumWindows($cb,[IntPtr]::Zero)|Out-Null
$rect=$script:r
$mt=[FK]::GetCurrentThreadId(); $tt=0; [FK]::GetWindowThreadProcessId($script:mainHwnd,[ref]$tt)|Out-Null
$att=[FK]::AttachThreadInput($mt,$tt,$true)
[FK]::SetForegroundWindow($script:mainHwnd)|Out-Null
Start-Sleep -Milliseconds 400
if($att){[FK]::AttachThreadInput($mt,$tt,$false)|Out-Null}
$sx=$rect.Left+$CX; $sy=$rect.Top+$CY
[FK]::SetCursorPos($sx,$sy)|Out-Null
Start-Sleep -Milliseconds 200
[FK]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [FK]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 700
# SendKeys
$ws = New-Object -ComObject WScript.Shell
$ws.SendKeys($Text)
Start-Sleep -Milliseconds 800
Write-Output "clicked ($sx,$sy) sendkeys: $Text"
# capture 2x strip
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class Cap3 {
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
$dc=[Cap3]::GetDC([IntPtr]::Zero); $cdc=[Cap3]::CreateCompatibleDC($dc)
$bmp=[Cap3]::CreateCompatibleBitmap($dc,720,240)
[Cap3]::SelectObject($cdc,$bmp)|Out-Null
[Cap3]::BitBlt($cdc,0,0,720,240,$dc,$rect.Left+430,$rect.Top+610,0x00CC0020)|Out-Null
$b=[System.Drawing.Image]::FromHbitmap($bmp)
$b.Save('J:\codex-work\LUODA-v3.0.1\strip3.png',[System.Drawing.Imaging.ImageFormat]::Png)
[Cap2]::DeleteObject($bmp)
