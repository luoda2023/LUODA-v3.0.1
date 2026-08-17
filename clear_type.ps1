param([int]$CX=600, [int]$CY=750)
$ErrorActionPreference='Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class FT {
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
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] ins, int sz);
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public InputUnion U; }
  [StructLayout(LayoutKind.Explicit)] public struct InputUnion { [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public UIntPtr dwExtraInfo; }
  public const uint INPUT_KEYBOARD = 1;
  public const uint KEYEVENTF_KEYUP = 0x0002;
  public const uint VK_CONTROL = 0x11;
  public const uint VK_A = 0x41;
  public const uint VK_BACK = 0x08;
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public struct RECT { public int Left, Top, Right, Bottom; }
  public static void Key(uint vk, bool up) {
    INPUT[] i = new INPUT[1];
    i[0].type = INPUT_KEYBOARD; i[0].U.ki.wVk = (ushort)vk; i[0].U.ki.wScan = 0; i[0].U.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0u; i[0].U.ki.time = 0; i[0].U.ki.dwExtraInfo = UIntPtr.Zero;
    SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
  }
  public static void Chord(uint a, uint b) { Key(a,false); Key(b,false); Key(b,true); Key(a,true); }
}
"@
[void][FT]::SetProcessDPIAware()
$targetPid = (Get-Process LDesk).Id
$script:mainHwnd=[IntPtr]::Zero; $script:r=$null
$cb=[FT+EnumWindowsProc]{ param($hwnd,$lparam)
  $p=0; [FT]::GetWindowThreadProcessId($hwnd,[ref]$p)|Out-Null
  if($p -eq $targetPid -and [FT]::IsWindowVisible($hwnd)){
    $len=[FT]::GetWindowTextLength($hwnd); $sb=New-Object System.Text.StringBuilder($len+1)
    [FT]::GetWindowText($hwnd,$sb,$sb.Capacity)|Out-Null
    if($sb.ToString() -notmatch 'Remote Desktop'){ $rr=New-Object FT+RECT; [FT]::GetWindowRect($hwnd,[ref]$rr)|Out-Null; $script:mainHwnd=$hwnd; $script:r=$rr }
  }
  return $true
}
[FT]::EnumWindows($cb,[IntPtr]::Zero)|Out-Null
$rect=$script:r
$mt=[FT]::GetCurrentThreadId(); $tt=0; [FT]::GetWindowThreadProcessId($script:mainHwnd,[ref]$tt)|Out-Null
$att=[FT]::AttachThreadInput($mt,$tt,$true)
[FT]::SetForegroundWindow($script:mainHwnd)|Out-Null
Start-Sleep -Milliseconds 400
if($att){[FT]::AttachThreadInput($mt,$tt,$false)|Out-Null}
$sx=$rect.Left+$CX; $sy=$rect.Top+$CY
[FT]::SetCursorPos($sx,$sy)|Out-Null
Start-Sleep -Milliseconds 150
[FT]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [FT]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 500
[FT]::Chord([FT]::VK_CONTROL,[FT]::VK_A)
Start-Sleep -Milliseconds 200
[FT]::Key([FT]::VK_BACK,false); [FT]::Key([FT]::VK_BACK,true)
Start-Sleep -Milliseconds 300
# type via SendKeys
$ws = New-Object -ComObject WScript.Shell
$ws.SendKeys('TEST987')
Start-Sleep -Milliseconds 600
Write-Output "clicked ($sx,$sy), ctrl+A, backspace, typed TEST987"
