Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Focus3 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
[Focus3]::ShowWindow([IntPtr]198572, 9) | Out-Null
[Focus3]::SetForegroundWindow([IntPtr]198572) | Out-Null
Start-Sleep -Milliseconds 500
Write-Host "mstsc focused"
