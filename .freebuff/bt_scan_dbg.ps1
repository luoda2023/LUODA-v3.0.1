Add-Type @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct P1 {
  public uint dwSize;
  public int fReturnAuthenticated;
  public int fReturnRemembered;
  public int fReturnUnknown;
  public int fReturnConnected;
  public int fIssueInquiry;
  public byte cTimeoutMultiplier;
  public IntPtr hRadio;
}

public struct D1 {
  public uint dwSize;
  public ulong ullLong;
  public uint ulClassOfDevice;
  public int fConnected;
  public int fRemembered;
  public int fAuthenticated;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 248)] public string szName;
}

public static class S2 {
  [DllImport("bthprops.cpl", SetLastError = true)]
  public static extern IntPtr BluetoothFindFirstDevice(ref P1 pbtsp, ref D1 pbtdi);
}
"@
Write-Host ("P1 size: " + [System.Runtime.InteropServices.Marshal]::SizeOf([type][P1]))
Write-Host ("D1 size: " + [System.Runtime.InteropServices.Marshal]::SizeOf([type][D1]))
$p = New-Object P1
$p.dwSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][P1])
$p.fReturnAuthenticated = 1
$p.fReturnRemembered = 1
$p.fReturnUnknown = 1
$p.fReturnConnected = 1
$p.fIssueInquiry = 1
$p.cTimeoutMultiplier = [byte]1
$p.hRadio = [IntPtr]::Zero
$d = New-Object D1
$d.dwSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][D1])
Write-Host "starting scan..."
$f = [S2]::BluetoothFindFirstDevice([ref]$p, [ref]$d)
$err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
Write-Host ("find={0} lastError={1}" -f $f, $err)
if ($f -ne [IntPtr]::Zero) {
  Write-Host ("device: name={0} addr={1:X12}" -f $d.szName, $d.ullLong)
} else {
  Write-Host "no device handle"
}
