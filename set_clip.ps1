param([string]$Text = "FIXTEST-PASTE-0807")
$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class ClipSet {
  [DllImport("user32.dll", SetLastError=true)] public static extern bool OpenClipboard(IntPtr hWndNewOwner);
  [DllImport("user32.dll")] public static extern bool EmptyClipboard();
  [DllImport("user32.dll")] public static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);
  [DllImport("user32.dll")] public static extern bool CloseClipboard();
  [DllImport("kernel32.dll")] public static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);
  [DllImport("kernel32.dll")] public static extern IntPtr GlobalLock(IntPtr hMem);
  [DllImport("kernel32.dll")] public static extern bool GlobalUnlock(IntPtr hMem);
  [DllImport("kernel32.dll")] public static extern UIntPtr GlobalSize(IntPtr hMem);
  [DllImport("kernel32.dll")] public static extern IntPtr memcpy(IntPtr dst, IntPtr src, UIntPtr len);
  public const uint CF_UNICODETEXT = 13;
  public const uint GMEM_MOVEABLE = 0x0002;
  public static bool Set(string s) {
    for (int attempt = 0; attempt < 10; attempt++) {
      if (!OpenClipboard(IntPtr.Zero)) { System.Threading.Thread.Sleep(200); continue; }
      try {
        EmptyClipboard();
        byte[] bytes = Encoding.Unicode.GetBytes(s + "\0");
        IntPtr hMem = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)bytes.Length);
        if (hMem == IntPtr.Zero) return false;
        IntPtr dst = GlobalLock(hMem);
        if (dst == IntPtr.Zero) { GlobalFree(hMem); return false; }
        Marshal.Copy(bytes, 0, dst, bytes.Length);
        GlobalUnlock(hMem);
        IntPtr hData = SetClipboardData(CF_UNICODETEXT, hMem);
        if (hData == IntPtr.Zero) { GlobalFree(hMem); return false; }
        return true;
      } finally { CloseClipboard(); }
    }
    return false;
  }
  [DllImport("kernel32.dll")] public static extern IntPtr GlobalFree(IntPtr hMem);
}
"@
$ok = [ClipSet]::Set($Text)
Write-Host "clipboard set: $ok ($Text)"
if (-not $ok) { exit 1 }
# verify clipboard
Add-Type -AssemblyName System.Windows.Forms
$c = [System.Windows.Forms.Clipboard]::GetText()
Write-Host "clipboard readback: $c"
