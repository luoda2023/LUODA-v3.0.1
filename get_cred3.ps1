Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CredUtil2 {
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool CredRead(string target, int type, int reserved, out IntPtr credential);
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool CredFree(IntPtr cred);
  [StructLayout(LayoutKind.Sequential)]
  public struct CREDENTIAL {
    public int Flags;
    public int Type;
    public IntPtr TargetName;
    public IntPtr Comment;
    public long LastWritten;
    public int CredentialBlobSize;
    public IntPtr CredentialBlob;
    public int Persist;
    public int AttributeCount;
    public IntPtr Attributes;
    public IntPtr TargetAlias;
    public IntPtr UserName;
  }
}
"@
foreach ($t in @("TERMSRV/36.134.211.189", "36.134.211.189", "TERMSRV/36.134.211.189:3389")) {
  foreach ($type in @(1, 3)) {
    $ptr = [IntPtr]::Zero
    if ([CredUtil2]::CredRead($t, $type, 0, [ref]$ptr)) {
      $cred = [System.Runtime.InteropServices.Marshal]::PtrToStructure($ptr, [type][CredUtil2+CREDENTIAL])
      $user = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($cred.UserName)
      $blob = New-Object byte[] $cred.CredentialBlobSize
      [System.Runtime.InteropServices.Marshal]::Copy($cred.CredentialBlob, $blob, 0, $cred.CredentialBlobSize)
      $pass = [System.Text.Encoding]::Unicode.GetString($blob)
      Write-Host "TARGET=$t TYPE=$type USER=$user PASS=$pass"
      [CredUtil2]::CredFree($ptr) | Out-Null
    } else {
      Write-Host "TARGET=$t TYPE=$type -> not found ($([System.Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
    }
  }
}
