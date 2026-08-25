Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinRestore {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
$p = Get-Process -Id 30096
[WinRestore]::ShowWindow($p.MainWindowHandle, 9)
Start-Sleep -Milliseconds 300
[WinRestore]::SetForegroundWindow($p.MainWindowHandle)
Write-Host "Window restored"
