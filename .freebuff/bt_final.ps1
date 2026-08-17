Add-Type @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct RP { public uint dwSize; }

[StructLayout(LayoutKind.Sequential)]
public struct RI {
  public uint dwSize;
  public ulong address;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 248)] public string szName;
  public uint ulClassOfDevice;
  public ushort lmpSubversion;
  public ushort manufacturer;
}

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

public static class BT {
  [DllImport("bthprops.cpl", SetLastError = true)]
  public static extern IntPtr BluetoothFindFirstRadio(ref RP p, out IntPtr phRadio);
  [DllImport("bthprops.cpl", SetLastError = true)]
  public static extern int BluetoothGetRadioInfo(IntPtr hRadio, ref RI info);
  [DllImport("bthprops.cpl")]
  public static extern int BluetoothFindRadioClose(IntPtr hFind);
  [DllImport("bthprops.cpl", SetLastError = true)]
  public static extern IntPtr BluetoothFindFirstDevice(ref SP p, ref DI d);
  [DllImport("bthprops.cpl")]
  public static extern int BluetoothFindNextDevice(IntPtr hFind, ref DI d);
  [DllImport("bthprops.cpl")]
  public static extern int BluetoothFindDeviceClose(IntPtr hFind);
  [DllImport("kernel32.dll")]
  public static extern bool CloseHandle(IntPtr h);
}
"@
Write-Host ("RP={0} RI={1} SP={2} DI={3}" -f [System.Runtime.InteropServices.Marshal]::SizeOf([type][RP]), [System.Runtime.InteropServices.Marshal]::SizeOf([type][RI]), [System.Runtime.InteropServices.Marshal]::SizeOf([type][SP]), [System.Runtime.InteropServices.Marshal]::SizeOf([type][DI]))
$rp = New-Object RP
$rp.dwSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][RP])
$radio = [IntPtr]::Zero
$findRadio = [BT]::BluetoothFindFirstRadio([ref]$rp, [ref]$radio)
Write-Host ("findRadio={0} radio={1} err={2}" -f $findRadio, $radio, [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
if ($radio -ne [IntPtr]::Zero) {
  $ri = New-Object RI
  $ri.dwSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][RI])
  $rc = [BT]::BluetoothGetRadioInfo($radio, [ref]$ri)
  Write-Host ("radio info rc={0} name={1} addr={2:X12}" -f $rc, $ri.szName, $ri.address)
}
$sp = New-Object SP
$sp.dwSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][SP])
$sp.fReturnAuthenticated = 1
$sp.fReturnRemembered = 1
$sp.fReturnUnknown = 1
$sp.fReturnConnected = 1
$sp.fIssueInquiry = 1
$sp.cTimeoutMultiplier = [byte]1
$sp.hRadio = $radio
$di = New-Object DI
$di.dwSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][DI])
Write-Host "discovery with radio handle (~10s)..."
$f = [BT]::BluetoothFindFirstDevice([ref]$sp, [ref]$di)
Write-Host ("find={0} err={1}" -f $f, [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
if ($f -ne [IntPtr]::Zero) {
  $n = 0
  do {
    $name = if ($di.szName -eq "") { "(unnamed)" } else { $di.szName }
    Write-Host ("  [{0}] {1} {2:X12}" -f $n, $name, $di.Address)
    $n++
  } while ([BT]::BluetoothFindNextDevice($f, [ref]$di) -eq 0)
  Write-Host ("  total {0}" -f $n)
  [BT]::BluetoothFindDeviceClose($f) | Out-Null
} else {
  Write-Host "no devices"
}
if ($findRadio -ne [IntPtr]::Zero) { [BT]::BluetoothFindRadioClose($findRadio) | Out-Null }
if ($radio -ne [IntPtr]::Zero) { [BT]::CloseHandle($radio) | Out-Null }
