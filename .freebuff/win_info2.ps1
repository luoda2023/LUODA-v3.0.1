Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WinInfo {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder sb, int max);
}
"@
$h = [IntPtr]2426540
$t = New-Object System.Text.StringBuilder 256
$c = New-Object System.Text.StringBuilder 256
[WinInfo]::GetWindowTextW($h, $t, 256) | Out-Null
[WinInfo]::GetClassNameW($h, $c, 256) | Out-Null
$bytes = [System.Text.Encoding]::Unicode.GetBytes($t.ToString())
Write-Output ("title='" + $t.ToString() + "' class='" + $c.ToString() + "'")
Write-Output ("title hex: " + (($bytes | ForEach-Object { $_.ToString('X2') }) -join ' '))
