param([int]$CX=470, [int]$CY=710)
$ErrorActionPreference='Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class ST {
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
  public const uint KEYEVENTF_UNICODE = 0x0004;
  public const uint KEYEVENTF_KEYUP = 0x0002;
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public struct RECT { public int Left, Top, Right, Bottom; }
  public static void SendUni(string s) {
    foreach (char c in s) {
      INPUT[] d = new INPUT[1];
      d[0].type = INPUT_KEYBOARD; d[0].U.ki.wVk = 0; d[0].U.ki.wScan = (ushort)c; d[0].U.ki.dwFlags = KEYEVENTF_UNICODE; d[0].U.ki.time = 0; d[0].U.ki.dwExtraInfo = UIntPtr.Zero;
      INPUT[] u = new INPUT[1];
      u[0].type = INPUT_KEYBOARD; u[0].U.ki.wVk = 0; u[0].U.ki.wScan = (ushort)c; u[0].U.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP; u[0].U.ki.time = 0; u[0].U.ki.dwExtraInfo = UIntPtr.Zero;
      SendInput(1, d, Marshal.SizeOf(typeof(INPUT)));
      SendInput(1, u, Marshal.SizeOf(typeof(INPUT)));
    }
  }
}
"@
[void][ST]::SetProcessDPIAware()
$targetPid = (Get-Process LDesk).Id
$script:mainHwnd=[IntPtr]::Zero; $script:r=$null
$cb=[ST+EnumWindowsProc]{ param($hwnd,$lparam)
  $p=0; [ST]::GetWindowThreadProcessId($hwnd,[ref]$p)|Out-Null
  if($p -eq $targetPid -and [ST]::IsWindowVisible($hwnd)){
    $len=[ST]::GetWindowTextLength($hwnd); $sb=New-Object System.Text.StringBuilder($len+1)
    [ST]::GetWindowText($hwnd,$sb,$sb.Capacity)|Out-Null
    if($sb.ToString() -notmatch 'Remote Desktop'){ $rr=New-Object ST+RECT; [ST]::GetWindowRect($hwnd,[ref]$rr)|Out-Null; $script:mainHwnd=$hwnd; $script:r=$rr }
  }
  return $true
}
[ST]::EnumWindows($cb,[IntPtr]::Zero)|Out-Null
$rect=$script:r
Write-Output "MAIN rect=($($rect.Left),$($rect.Top),$($rect.Right),$($rect.Bottom))"
$mt=[ST]::GetCurrentThreadId(); $tt=0; [ST]::GetWindowThreadProcessId($script:mainHwnd,[ref]$tt)|Out-Null
$att=[ST]::AttachThreadInput($mt,$tt,$true)
[ST]::SetForegroundWindow($script:mainHwnd)|Out-Null
Start-Sleep -Milliseconds 400
if($att){[ST]::AttachThreadInput($mt,$tt,$false)|Out-Null}
$sx=$rect.Left+$CX; $sy=$rect.Top+$CY
[ST]::SetCursorPos($sx,$sy)|Out-Null
Start-Sleep -Milliseconds 200
[ST]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [ST]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 700
[ST]::SendUni('HELLO')
Start-Sleep -Milliseconds 500
Write-Output "clicked ($sx,$sy) window-local ($CX,$CY), typed HELLO"
