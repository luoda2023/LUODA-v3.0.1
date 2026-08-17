param([int]$X = 0, [int]$Y = 0, [int]$DragToX = 0, [int]$DragToY = 0)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class PM {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wp, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
}
'@
# 找到主 FLUTTER_RUNNER 窗口（含 FLUTTERVIEW 子窗口的那个）
$main = [IntPtr]::Zero
$cb1 = {
  param($h, $lp)
  $sb = New-Object System.Text.StringBuilder 128
  [PM]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq 'FLUTTER_RUNNER_WIN32_WINDOW' -and [PM]::IsWindowVisible($h)) {
    $script:main = $h
  }
  return $true
}
[PM]::EnumWindows($cb1, [IntPtr]::Zero) | Out-Null
if ($script:main -eq [IntPtr]::Zero) { Write-Output 'NO_MAIN'; exit 1 }
# 找 FLUTTERVIEW 子窗口
$fv = [IntPtr]::Zero
$cb2 = {
  param($h, $lp)
  $sb = New-Object System.Text.StringBuilder 128
  [PM]::GetClassName($h, $sb, 128) | Out-Null
  if ($sb.ToString() -eq 'FLUTTERVIEW') { $script:fv = $h; return $false }
  return $true
}
[PM]::EnumChildWindows($script:main, $cb2, [IntPtr]::Zero) | Out-Null
if ($script:fv -eq [IntPtr]::Zero) { Write-Output 'NO_FV'; exit 1 }
[PM]::ShowWindow($script:main, 9) | Out-Null
[PM]::SetForegroundWindow($script:main) | Out-Null
Start-Sleep -Milliseconds 400
function MakeLp([int]$cx, [int]$cy) {
  return [IntPtr]((($cy -band 0xFFFF) -shl 16) -bor ($cx -band 0xFFFF))
}
# 点击序列
$lp = MakeLp $X $Y
[PM]::PostMessage($script:fv, 0x0200, [IntPtr]0, $lp) | Out-Null        # WM_MOUSEMOVE
Start-Sleep -Milliseconds 80
[PM]::PostMessage($script:fv, 0x0201, [IntPtr]1, $lp) | Out-Null        # WM_LBUTTONDOWN
Start-Sleep -Milliseconds 120
[PM]::PostMessage($script:fv, 0x0202, [IntPtr]0, $lp) | Out-Null        # WM_LBUTTONUP
if ($DragToX -ne 0 -or $DragToY -ne 0) {
  # 拖拽：从起点按住移动到终点再释放
  $steps = 12
  for ($i = 1; $i -le $steps; $i++) {
    $dx = $X + [int](($DragToX - $X) * $i / $steps)
    $dy = $Y + [int](($DragToY - $Y) * $i / $steps)
    $lp2 = MakeLp $dx $dy
    [PM]::PostMessage($script:fv, 0x0200, [IntPtr]1, $lp2) | Out-Null  # WM_MOUSEMOVE with MK_LBUTTON
    Start-Sleep -Milliseconds 30
  }
  $lp3 = MakeLp $DragToX $DragToY
  [PM]::PostMessage($script:fv, 0x0202, [IntPtr]0, $lp3) | Out-Null    # WM_LBUTTONUP
}
Write-Output "pm-click ($X,$Y) drag=($DragToX,$DragToY) main=$script:main fv=$script:fv"
