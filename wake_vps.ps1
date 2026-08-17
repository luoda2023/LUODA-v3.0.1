Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KeySend {
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
}
"@
# Move mouse inside RDP and click, then press Win key
[KeySend]::SetCursorPos(600, 300) | Out-Null
[KeySend]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
[KeySend]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 300
# Send Winkey (0x5B)
[KeySend]::keybd_event(0x5B, 0, 0, [UIntPtr]::Zero)
[KeySend]::keybd_event(0x5B, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 800
# Press Esc to close start menu
[KeySend]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero)
[KeySend]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 300
Write-Host "keys sent"
