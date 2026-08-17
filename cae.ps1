Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KeySend2 {
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
[KeySend2]::SetForegroundWindow([IntPtr]198572) | Out-Null
Start-Sleep -Milliseconds 300
# Ctrl+Alt+End
[KeySend2]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)   # Ctrl down
[KeySend2]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)   # Alt down
[KeySend2]::keybd_event(0x23, 0, 0, [UIntPtr]::Zero)   # End down
[KeySend2]::keybd_event(0x23, 0, 2, [UIntPtr]::Zero)   # End up
[KeySend2]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)   # Alt up
[KeySend2]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)   # Ctrl up
Start-Sleep -Milliseconds 1500
Write-Host "ctrl+alt+end sent"
