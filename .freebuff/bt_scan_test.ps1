Add-Type @"
using System;
using System.Runtime.InteropServices;

public struct BT_DEV_SEARCH_PARAMS {
  public uint dwSize;
  public int fReturnAuthenticated;
  public int fReturnRemembered;
  public int fReturnUnknown;
  public int fReturnConnected;
  public int fIssueInquiry;
  public byte cTimeoutMultiplier;
  public IntPtr hRadio;
}

public struct BT_ADDR {
  public ulong ullLong;
}

public struct BT_DEV_INFO {
  public uint dwSize;
  public BT_ADDR Address;
  public uint ulClassOfDevice;
  public int fConnected;
  public int fRemembered;
  public int fAuthenticated;
  public Guid stDefaultService;
  public Guid stService1;
  public Guid stService2;
  public Guid stService3;
  public Guid stService4;
  public Guid stService5;
  public Guid stService6;
  public Guid stService7;
  public Guid stService8;
  public Guid stService9;
  public Guid stService10;
  public Guid stService11;
  public Guid stService12;
  public Guid stService13;
  public Guid stService14;
  public Guid stService15;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 248)] public string szName;
}

public static class BtScan {
  [DllImport("bthprops.cpl", SetLastError = true)]
  public static extern IntPtr BluetoothFindFirstDevice(ref BT_DEV_SEARCH_PARAMS pbtsp, ref BT_DEV_INFO pbtdi);
  [DllImport("bthprops.cpl")]
  public static extern int BluetoothFindNextDevice(IntPtr hFind, ref BT_DEV_INFO pbtdi);
  [DllImport("bthprops.cpl")]
  public static extern int BluetoothFindDeviceClose(IntPtr hFind);
}
"@
$search = New-Object BT_DEV_SEARCH_PARAMS
$search.dwSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][BT_DEV_SEARCH_PARAMS])
$search.fReturnAuthenticated = 1
$search.fReturnRemembered = 1
$search.fReturnUnknown = 1
$search.fReturnConnected = 1
$search.fIssueInquiry = 1
$search.cTimeoutMultiplier = [byte]2
$search.hRadio = [IntPtr]::Zero
$dev = New-Object BT_DEV_INFO
$dev.dwSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][BT_DEV_INFO])
Write-Host "starting discovery (this takes ~10s)..."
$find = [BtScan]::BluetoothFindFirstDevice([ref]$search, [ref]$dev)
Write-Host ("find handle: " + $find)
if ($find -ne [IntPtr]::Zero) {
  $n = 0
  do {
    $name = if ($dev.szName -eq "") { "(unnamed)" } else { $dev.szName }
    Write-Host ("  found[{0}]: name={1} addr={2:X12} conn={3} auth={4} rem={5}" -f $n, $name, $dev.Address.ullLong, $dev.fConnected, $dev.fAuthenticated, $dev.fRemembered)
    $n++
  } while ([BtScan]::BluetoothFindNextDevice($find, [ref]$dev) -eq 0)
  Write-Host ("  total found: " + $n)
  [BtScan]::BluetoothFindDeviceClose($find) | Out-Null
} else {
  Write-Host ("no devices / find failed, lastError=" + [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
}
