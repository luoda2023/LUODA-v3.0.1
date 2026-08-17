Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KeyOps {
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr hWnd);
}
"@
[KeyOps]::SetForegroundWindow([IntPtr]592070) | Out-Null
Start-Sleep -Milliseconds 400
[KeyOps]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero)  # Esc
[KeyOps]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 600
Write-Host "esc sent"
