Add-Type @"
using System;
using System.Runtime.InteropServices;

public struct BLUETOOTH_RADIO_INFO {
  public uint dwSize;
  public ulong address;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 248)] public string szName;
  public uint ulClassOfDevice;
  public ushort lmpSubversion;
  public ushort manufacturer;
}

public struct BLUETOOTH_FIND_RADIO_PARAMS {
  public uint dwSize;
}

public struct BLUETOOTH_DEVICE_SEARCH_PARAMS {
  public uint dwSize;
  public int fReturnAuthenticated;
  public int fReturnRemembered;
  public int fReturnUnknown;
  public int fReturnConnected;
  public int fIssueInquiry;
  public byte cTimeoutMultiplier;
  public IntPtr hRadio;
}

public struct BLUETOOTH_ADDRESS {
  public ulong ullLong;
}

public struct BLUETOOTH_DEVICE_INFO {
  public uint dwSize;
  public BLUETOOTH_ADDRESS Address;
  public uint ulClassOfDevice;
  public int fConnected;
  public int fRemembered;
  public int fAuthenticated;
  public System.Guid stDefaultService;
  public System.Guid stService1;
  public System.Guid stService2;
  public System.Guid stService3;
  public System.Guid stService4;
  public System.Guid stService5;
  public System.Guid stService6;
  public System.Guid stService7;
  public System.Guid stService8;
  public System.Guid stService9;
  public System.Guid stService10;
  public System.Guid stService11;
  public System.Guid stService12;
  public System.Guid stService13;
  public System.Guid stService14;
  public System.Guid stService15;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 248)] public string szName;
}

public static class BtApi {
  [DllImport("bthprops.cpl", SetLastError = true)]
  public static extern IntPtr BluetoothFindFirstRadio(ref BLUETOOTH_FIND_RADIO_PARAMS pbtfrp, out IntPtr phRadio);

  [DllImport("bthprops.cpl")]
  public static extern int BluetoothGetRadioInfo(IntPtr hRadio, ref BLUETOOTH_RADIO_INFO pRadioInfo);

  [DllImport("bthprops.cpl")]
  public static extern int BluetoothFindRadioClose(IntPtr hFind);

  [DllImport("bthprops.cpl", SetLastError = true)]
  public static extern IntPtr BluetoothFindFirstDevice(ref BLUETOOTH_DEVICE_SEARCH_PARAMS pbtsp, ref BLUETOOTH_DEVICE_INFO pbtdi);

  [DllImport("bthprops.cpl")]
  public static extern int BluetoothFindNextDevice(IntPtr hFind, ref BLUETOOTH_DEVICE_INFO pbtdi);

  [DllImport("bthprops.cpl")]
  public static extern int BluetoothFindDeviceClose(IntPtr hFind);

  [DllImport("kernel32.dll")]
  public static extern bool CloseHandle(IntPtr hObject);
}
"@

# 1. Radio
$params = New-Object BLUETOOTH_FIND_RADIO_PARAMS
$params.dwSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][BLUETOOTH_FIND_RADIO_PARAMS])
$radioHandle = [IntPtr]::Zero
$find = [BtApi]::BluetoothFindFirstRadio([ref]$params, [ref]$radioHandle)
Write-Host ("radio find handle: " + $find)
if ($find -ne [IntPtr]::Zero) {
  $info = New-Object BLUETOOTH_RADIO_INFO
  $info.dwSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][BLUETOOTH_RADIO_INFO])
  $rc = [BtApi]::BluetoothGetRadioInfo($radioHandle, [ref]$info)
  Write-Host ("GetRadioInfo rc={0} name={1} address={2:X12} manufacturer={3}" -f $rc, $info.szName, $info.address, $info.manufacturer)
} else {
  Write-Host ("no radio, lastError=" + [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
}

# 2. Paired devices
$search = New-Object BLUETOOTH_DEVICE_SEARCH_PARAMS
$search.dwSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][BLUETOOTH_DEVICE_SEARCH_PARAMS])
$search.fReturnAuthenticated = 1
$search.fReturnRemembered = 1
$search.fReturnConnected = 1
$search.fReturnUnknown = 0
$search.fIssueInquiry = 0
$search.hRadio = [IntPtr]::Zero
$dev = New-Object BLUETOOTH_DEVICE_INFO
$dev.dwSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][BLUETOOTH_DEVICE_INFO])
$devFind = [BtApi]::BluetoothFindFirstDevice([ref]$search, [ref]$dev)
Write-Host "--- paired/known devices ---"
$n = 0
while ($devFind -ne [IntPtr]::Zero) {
  Write-Host ("  device[{0}]: name={1} addr={2:X12} conn={3} auth={4}" -f $n, $dev.szName, $dev.Address.ullLong, $dev.fConnected, $dev.fAuthenticated)
  $n++
  if ([BtApi]::BluetoothFindNextDevice($devFind, [ref]$dev) -ne 0) { break }
}
if ($devFind -ne [IntPtr]::Zero) { [BtApi]::BluetoothFindDeviceClose($devFind) | Out-Null }
Write-Host ("  total: " + $n)
if ($find -ne [IntPtr]::Zero) {
  [BtApi]::BluetoothFindRadioClose($find) | Out-Null
  [BtApi]::CloseHandle($radioHandle) | Out-Null
}
