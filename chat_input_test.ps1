param(
  [string]$Text = "FIXTEST-0807",
  [int]$X = 1879,
  [int]$Y = 741,
  [switch]$PressEnter
)
$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class ChatInput {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr info);
  [DllImport("user32.dll")] public static extern uint SendInput(uint nInputs, INPUT[] inputs, int cbSize);
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public InputUnion U; }
  [StructLayout(LayoutKind.Explicit)] public struct InputUnion { [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public UIntPtr dwExtraInfo; }
  public const uint INPUT_KEYBOARD = 1;
  public const uint KEYEVENTF_UNICODE = 0x0004;
  public const uint KEYEVENTF_KEYUP = 0x0002;
  public const uint LEFTDOWN = 0x0002;
  public const uint LEFTUP = 0x0004;
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public struct RECT { public int Left, Top, Right, Bottom; }
  public static void SendUnicode(string s) {
    foreach (char c in s) {
      INPUT[] down = new INPUT[1];
      down[0].type = INPUT_KEYBOARD;
      down[0].U.ki.wVk = 0; down[0].U.ki.wScan = (ushort)c;
      down[0].U.ki.dwFlags = KEYEVENTF_UNICODE; down[0].U.ki.time = 0; down[0].U.ki.dwExtraInfo = UIntPtr.Zero;
      INPUT[] up = new INPUT[1];
      up[0].type = INPUT_KEYBOARD;
      up[0].U.ki.wVk = 0; up[0].U.ki.wScan = (ushort)c;
      up[0].U.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP; up[0].U.ki.time = 0; up[0].U.ki.dwExtraInfo = UIntPtr.Zero;
      SendInput(1, down, Marshal.SizeOf(typeof(INPUT)));
      SendInput(1, up, Marshal.SizeOf(typeof(INPUT)));
    }
  }
  public static void SendEnter() {
    INPUT[] down = new INPUT[1];
    down[0].type = INPUT_KEYBOARD;
    down[0].U.ki.wVk = 0x0D; down[0].U.ki.wScan = 0; down[0].U.ki.dwFlags = 0; down[0].U.ki.time = 0; down[0].U.ki.dwExtraInfo = UIntPtr.Zero;
    INPUT[] up = new INPUT[1];
    up[0].type = INPUT_KEYBOARD;
    up[0].U.ki.wVk = 0x0D; up[0].U.ki.wScan = 0; up[0].U.ki.dwFlags = KEYEVENTF_KEYUP; up[0].U.ki.time = 0; up[0].U.ki.dwExtraInfo = UIntPtr.Zero;
    SendInput(1, down, Marshal.SizeOf(typeof(INPUT)));
    SendInput(1, up, Marshal.SizeOf(typeof(INPUT)));
  }
}
"@
[void][ChatInput]::SetProcessDPIAware()

# find LDesk main window (the one without "Remote Desktop" in title)
$targetPid = (Get-Process LDesk).Id
$main = [IntPtr]::Zero
$cb = [ChatInput+EnumWindowsProc]{
  param($hwnd, $lparam)
  $pid2 = 0
  [ChatInput]::GetWindowThreadProcessId($hwnd, [ref]$pid2) | Out-Null
  if ($pid2 -eq $targetPid -and [ChatInput]::IsWindowVisible($hwnd)) {
    $len = [ChatInput]::GetWindowTextLength($hwnd)
    $sb = New-Object System.Text.StringBuilder($len + 1)
    [ChatInput]::GetWindowText($hwnd, $sb, $sb.Capacity) | Out-Null
    $t = $sb.ToString()
    $r = New-Object ChatInput+RECT
    [ChatInput]::GetWindowRect($hwnd, [ref]$r) | Out-Null
    if ($t -notmatch 'Remote Desktop') {
      $script:main = $hwnd
      Write-Host ("MAIN hwnd={0} rect=({1},{2},{3},{4}) title='{5}'" -f $hwnd, $r.Left, $r.Top, $r.Right, $r.Bottom, $t)
    } else {
      Write-Host ("REMOTE hwnd={0} rect=({1},{2},{3},{4})" -f $hwnd, $r.Left, $r.Top, $r.Right, $r.Bottom)
    }
  }
  return $true
}
[ChatInput]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
if ($script:main -eq [IntPtr]::Zero) { Write-Host 'NO MAIN WINDOW'; exit 1 }
$mainHwnd = [IntPtr]$script:main

# bring to foreground with attach trick
$fgThread = [ChatInput]::GetWindowThreadProcessId([ChatInput]::GetForegroundWindow(), [ref]$null)
$myThread = [ChatInput]::GetCurrentThreadId()
[ChatInput]::GetWindowThreadProcessId($mainHwnd, [ref]$null) | Out-Null
$targetTid = 0
[ChatInput]::GetWindowThreadProcessId($mainHwnd, [ref]$targetTid) | Out-Null
$attached = [ChatInput]::AttachThreadInput($myThread, $targetTid, $true)
[ChatInput]::SetForegroundWindow($mainHwnd) | Out-Null
[ChatInput]::SetWindowPos($mainHwnd, [IntPtr]::Zero, 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0040) | Out-Null
Start-Sleep -Milliseconds 400
if ($attached) { [ChatInput]::AttachThreadInput($myThread, $targetTid, $false) | Out-Null }

# click input box
[ChatInput]::SetCursorPos($X, $Y) | Out-Null
Start-Sleep -Milliseconds 150
[ChatInput]::mouse_event([ChatInput]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
[ChatInput]::mouse_event([ChatInput]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 500

$fg = [ChatInput]::GetForegroundWindow()
Write-Host ("foreground after focus: {0} (main={1})" -f $fg, $mainHwnd)

# type text
[ChatInput]::SendUnicode($Text)
Start-Sleep -Milliseconds 300
if ($PressEnter) { [ChatInput]::SendEnter(); Write-Host 'enter pressed' }
Write-Host ("typed: $Text")
