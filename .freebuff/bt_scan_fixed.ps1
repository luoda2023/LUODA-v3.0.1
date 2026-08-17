Add-Type @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct SP {
  public uint dwSize;
  public int fReturnAuthenticated;
  public int fReturnRemembered;
  public int fReturnUnknown;
  public int fReturnConnected;
  public int fIssueInquiry;
  public byte cTimeoutMultiplier;
  public IntPtr hRadio;
}

[StructLayout(LayoutKind.Sequential)]
public struct DI {
  public uint dwSize;
  public ulong Address;
  public uint ulClassOfDevice;
  public int fConnected;
  public int fRemembered;
  public int fAuthenticated;
  public Guid stDefaultService;
  [MarshalAs(UnmanagedType.ByValArray, SizeConst = 15)] public Guid[] stServices;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 248)] public string szName;
}

public static class S3 {
  [DllImport("bthprops.cpl", SetLastError = true)]
  public static extern IntPtr BluetoothFindFirstDevice(ref SP pbtsp, ref DI pbtdi);
  [DllImport("bthprops.cpl")]
  public static extern int BluetoothFindNextDevice(IntPtr hFind, ref DI pbtdi);
  [DllImport("bthprops.cpl")]
  public static extern int BluetoothFindDeviceClose(IntPtr hFind);
}
"@
Write-Host ("SP size: " + [System.Runtime.InteropServices.Marshal]::SizeOf([type][SP]))
Write-Host ("DI size: " + [System.Runtime.InteropServices.Marshal]::SizeOf([type][DI]))
$p = New-Object SP
$p.dwSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][SP])
$p.fReturnAuthenticated = 1
$p.fReturnRemembered = 1
$p.fReturnUnknown = 1
$p.fReturnConnected = 1
$p.fIssueInquiry = 1
$p.cTimeoutMultiplier = [byte]2
$p.hRadio = [IntPtr]::Zero
$d = New-Object DI
$d.dwSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][DI])
Write-Host "starting discovery (~10s)..."
$f = [S3]::BluetoothFindFirstDevice([ref]$p, [ref]$d)
$err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
Write-Host ("find={0} lastError={1}" -f $f, $err)
if ($f -ne [IntPtr]::Zero) {
  $n = 0
  do {
    $name = if ($d.szName -eq "") { "(unnamed)" } else { $d.szName }
    Write-Host ("  found[{0}]: name={1} addr={2:X12}" -f $n, $name, $d.Address)
    $n++
  } while ([S3]::BluetoothFindNextDevice($f, [ref]$d) -eq 0)
  Write-Host ("  total: " + $n)
  [S3]::BluetoothFindDeviceClose($f) | Out-Null
} else {
  Write-Host "no devices found"
}
