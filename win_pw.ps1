Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Cap3 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
}
"@
$h=[IntPtr]56953654
$r=New-Object Cap3+RECT
[Cap3]::GetWindowRect($h,[ref]$r)|Out-Null
$w=$r.R-$r.L; $hh=$r.B-$r.T
$bmp=New-Object System.Drawing.Bitmap($w,$hh)
$g=[System.Drawing.Graphics]::FromImage($bmp)
$dc=$g.GetHdc()
$ok=[Cap3]::PrintWindow($h,$dc,2)
$g.ReleaseHdc($dc); $g.Dispose()
$bmp.Save("J:\codex-work\LUODA-v3.0.1\_win_pw.png",[System.Drawing.Imaging.ImageFormat]::Png)
Write-Output "PrintWindow ok=$ok size=$w x $hh"
$bmp.Dispose()
