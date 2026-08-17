param(
  [string]$Text = "FIXTEST-0807",
  [switch]$PressEnter
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($WinRtTask, $ResultType) {
  $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
  $netTask = $asTask.Invoke($null, @($WinRtTask))
  $netTask.Wait(-1) | Out-Null
  $netTask.Result
}
function Get-OcrLines([string]$Path) {
  $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
  $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)) ([Windows.Storage.StorageFile])
  $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
  $lines = @()
  foreach ($line in $result.Lines) {
    $firstW = $line.Words | Select-Object -First 1
    $lastW = $line.Words | Select-Object -Last 1
    $lines += [PSCustomObject]@{ Text = $line.Text; X = [int]$firstW.BoundingRect.X; Y = [int]$firstW.BoundingRect.Y; W = [int]($lastW.BoundingRect.Right - $firstW.BoundingRect.X); H = [int]$firstW.BoundingRect.Height }
  }
  return $lines
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class ChatInput2 {
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
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
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
  public const uint VK_RETURN = 0x0D;
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
    down[0].U.ki.wVk = (ushort)VK_RETURN; down[0].U.ki.wScan = 0; down[0].U.ki.dwFlags = 0; down[0].U.ki.time = 0; down[0].U.ki.dwExtraInfo = UIntPtr.Zero;
    INPUT[] up = new INPUT[1];
    up[0].type = INPUT_KEYBOARD;
    up[0].U.ki.wVk = (ushort)VK_RETURN; up[0].U.ki.wScan = 0; up[0].U.ki.dwFlags = KEYEVENTF_KEYUP; up[0].U.ki.time = 0; up[0].U.ki.dwExtraInfo = UIntPtr.Zero;
    SendInput(1, down, Marshal.SizeOf(typeof(INPUT)));
    SendInput(1, up, Marshal.SizeOf(typeof(INPUT)));
  }
}
"@
[void][ChatInput2]::SetProcessDPIAware()

# 1) find main window
$targetPid = (Get-Process LDesk).Id
$script:mainHwnd = [IntPtr]::Zero
$script:mainRect = $null
$cb = [ChatInput2+EnumWindowsProc]{
  param($hwnd, $lparam)
  $p = 0
  [ChatInput2]::GetWindowThreadProcessId($hwnd, [ref]$p) | Out-Null
  if ($p -eq $targetPid -and [ChatInput2]::IsWindowVisible($hwnd)) {
    $len = [ChatInput2]::GetWindowTextLength($hwnd)
    $sb = New-Object System.Text.StringBuilder($len + 1)
    [ChatInput2]::GetWindowText($hwnd, $sb, $sb.Capacity) | Out-Null
    if ($sb.ToString() -notmatch 'Remote Desktop') {
      $r = New-Object ChatInput2+RECT
      [ChatInput2]::GetWindowRect($hwnd, [ref]$r) | Out-Null
      $script:mainHwnd = $hwnd
      $script:mainRect = $r
    }
  }
  return $true
}
[ChatInput2]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
if ($script:mainHwnd -eq [IntPtr]::Zero) { Write-Host 'NO MAIN WINDOW'; exit 1 }
$rect = $script:mainRect
Write-Host ("MAIN hwnd={0} rect=({1},{2},{3},{4})" -f $script:mainHwnd, $rect.Left, $rect.Top, $rect.Right, $rect.Bottom)

# 2) capture main window and OCR to locate input placeholder
$png = 'J:\codex-work\LUODA-v3.0.1\main_win.png'
& 'J:\codex-work\LUODA-v3.0.1\shot_dpi.ps1' -X $rect.Left -Y $rect.Top -W ($rect.Right - $rect.Left) -H ($rect.Bottom - $rect.Top) -Out $png | Out-Null
$lines = Get-OcrLines $png
$maxY = ($lines | ForEach-Object Y | Measure-Object -Maximum).Maximum; $inputLine = $lines | Where-Object { (($_.Text -replace '\s','') -match '输入') -and $_.Y -gt $maxY * 0.55 } | Select-Object -Last 1
if (-not $inputLine) { $inputLine = $lines | Where-Object { $_.Text -match '输入' } | Select-Object -Last 1 }
if (-not $inputLine) { Write-Host 'INPUT LINE NOT FOUND'; $lines | ForEach-Object { Write-Host ("OCR: ({0},{1}) {2}" -f $_.X, $_.Y, $_.Text) }; exit 1 }
$cx = $rect.Left + $inputLine.X + [int]($inputLine.W / 2)
$cy = $rect.Top + $inputLine.Y + 20
Write-Host ("INPUT PLACEHOLDER at img({0},{1}) -> screen({2},{3}) text='{4}'" -f $inputLine.X, $inputLine.Y, $cx, $cy, $inputLine.Text)

# 3) focus main window
$fgBefore = [ChatInput2]::GetForegroundWindow()
$myThread = [ChatInput2]::GetCurrentThreadId()
$targetTid = 0
[ChatInput2]::GetWindowThreadProcessId($script:mainHwnd, [ref]$targetTid) | Out-Null
$attached = [ChatInput2]::AttachThreadInput($myThread, $targetTid, $true)
[ChatInput2]::SetForegroundWindow($script:mainHwnd) | Out-Null
[ChatInput2]::SetWindowPos($script:mainHwnd, [IntPtr]::Zero, 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0040) | Out-Null
Start-Sleep -Milliseconds 500
if ($attached) { [ChatInput2]::AttachThreadInput($myThread, $targetTid, $false) | Out-Null }
$fgAfter = [ChatInput2]::GetForegroundWindow()
Write-Host ("foreground: before={0} after={1} main={2} match={3}" -f $fgBefore, $fgAfter, $script:mainHwnd, ($fgAfter -eq $script:mainHwnd))

# 4) click input
[ChatInput2]::SetCursorPos($cx, $cy) | Out-Null
Start-Sleep -Milliseconds 200
[ChatInput2]::mouse_event([ChatInput2]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
[ChatInput2]::mouse_event([ChatInput2]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 600

# 5) type
[ChatInput2]::SendUnicode($Text)
Start-Sleep -Milliseconds 500
if ($PressEnter) {
  [ChatInput2]::SendEnter()
  Write-Host 'ENTER pressed'
}
Write-Host ("TYPED: $Text")

# 6) verify
Start-Sleep -Milliseconds 400
$png2 = 'J:\codex-work\LUODA-v3.0.1\main_after_type.png'
& 'J:\codex-work\LUODA-v3.0.1\shot_dpi.ps1' -X $rect.Left -Y $rect.Top -W ($rect.Right - $rect.Left) -H ($rect.Bottom - $rect.Top) -Out $png2 | Out-Null
$lines2 = Get-OcrLines $png2
$found = $lines2 | Where-Object { $_.Text -match [regex]::Escape($Text.Substring(0, [Math]::Min(8, $Text.Length))) }
if ($found) { Write-Host 'VERIFY: text visible in input box' } else { Write-Host 'VERIFY: text NOT found in OCR' }
$lines2 | ForEach-Object { Write-Host ("AFTER: ({0},{1}) {2}" -f $_.X, $_.Y, $_.Text) }




