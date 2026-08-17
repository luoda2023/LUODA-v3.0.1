Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CredUtil {
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
$ptr = [IntPtr]::Zero
if ([CredUtil]::CredRead("TERMSRV/36.134.211.189", 1, 0, [ref]$ptr)) {
  $cred = [System.Runtime.InteropServices.Marshal]::PtrToStructure($ptr, [type][CredUtil+CREDENTIAL])
  $user = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($cred.UserName)
  $blob = New-Object byte[] $cred.CredentialBlobSize
  [System.Runtime.InteropServices.Marshal]::Copy($cred.CredentialBlob, $blob, 0, $cred.CredentialBlobSize)
  $pass = [System.Text.Encoding]::Unicode.GetString($blob)
  Write-Host "USER=$user"
  Write-Host "PASS=$pass"
  [CredUtil]::CredFree($ptr) | Out-Null
} else {
  Write-Host ("CredRead failed: " + [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
}
