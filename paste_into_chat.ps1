param([string]$Text = "FIXTEST-PASTE-0807")
$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class PasteInput {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
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
  public const uint VK_V = 0x56;
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public struct RECT { public int Left, Top, Right, Bottom; }
  public static void Key(uint vk, bool up) {
    INPUT[] i = new INPUT[1];
    i[0].type = INPUT_KEYBOARD;
    i[0].U.ki.wVk = (ushort)vk; i[0].U.ki.wScan = 0; i[0].U.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0u; i[0].U.ki.time = 0; i[0].U.ki.dwExtraInfo = UIntPtr.Zero;
    SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
  }
  public static void CtrlV() { Key(VK_CONTROL, false); Key(VK_V, false); Key(VK_V, true); Key(VK_CONTROL, true); }
}
"@
[void][PasteInput]::SetProcessDPIAware()
$targetPid = (Get-Process LDesk).Id
$script:mainHwnd = [IntPtr]::Zero
$script:mainRect = $null
$cb = [PasteInput+EnumWindowsProc]{
  param($hwnd, $lparam)
  $p = 0
  [PasteInput]::GetWindowThreadProcessId($hwnd, [ref]$p) | Out-Null
  if ($p -eq $targetPid -and [PasteInput]::IsWindowVisible($hwnd)) {
    $len = [PasteInput]::GetWindowTextLength($hwnd)
    $sb = New-Object System.Text.StringBuilder($len + 1)
    [PasteInput]::GetWindowText($hwnd, $sb, $sb.Capacity) | Out-Null
    if ($sb.ToString() -notmatch 'Remote Desktop') {
      $r = New-Object PasteInput+RECT
      [PasteInput]::GetWindowRect($hwnd, [ref]$r) | Out-Null
      $script:mainHwnd = $hwnd; $script:mainRect = $r
    }
  }
  return $true
}
[PasteInput]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$rect = $script:mainRect
Write-Host ("MAIN rect=({0},{1},{2},{3})" -f $rect.Left, $rect.Top, $rect.Right, $rect.Bottom)
$myThread = [PasteInput]::GetCurrentThreadId()
$targetTid = 0
[PasteInput]::GetWindowThreadProcessId($script:mainHwnd, [ref]$targetTid) | Out-Null
$attached = [PasteInput]::AttachThreadInput($myThread, $targetTid, $true)
[PasteInput]::SetForegroundWindow($script:mainHwnd) | Out-Null
Start-Sleep -Milliseconds 500
if ($attached) { [PasteInput]::AttachThreadInput($myThread, $targetTid, $false) | Out-Null }
# click placeholder (window-local 465,706 -> screen)
$cx = $rect.Left + 465
$cy = $rect.Top + 706
[PasteInput]::SetCursorPos($cx, $cy) | Out-Null
Start-Sleep -Milliseconds 200
[PasteInput]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
[PasteInput]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 600
# click again then paste
[PasteInput]::SetCursorPos($cx, $cy) | Out-Null
Start-Sleep -Milliseconds 200
[PasteInput]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
[PasteInput]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 600
[PasteInput]::CtrlV()
Start-Sleep -Milliseconds 800
Write-Host "pasted at ($cx,$cy)"

