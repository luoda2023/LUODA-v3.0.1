# E2E helper: click / drag / double-click at physical pixel coordinates.
# Usage:
#   powershell -File e2e_click.ps1 click <x> <y>
#   powershell -File e2e_click.ps1 dblclick <x> <y>
#   powershell -File e2e_click.ps1 drag <x1> <y1> <x2> <y2> [ms]
param(
  [Parameter(Mandatory=$true)][string]$Action,
  [int]$X, [int]$Y, [int]$X2 = 0, [int]$Y2 = 0, [int]$DurMs = 600
)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class MouseHelper {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  public static void Down() { mouse_event(2, 0, 0, 0, UIntPtr.Zero); }
  public static void Up() { mouse_event(4, 0, 0, 0, UIntPtr.Zero); }
  [DllImport("user32.dll")] private static extern void mouse_event(uint f, uint dx, uint dy, uint data, UIntPtr extra);
}
'@

function Click([int]$cx, [int]$cy) {
  [MouseHelper]::SetCursorPos($cx, $cy) | Out-Null
  Start-Sleep -Milliseconds 150
  [MouseHelper]::Down()
  Start-Sleep -Milliseconds 60
  [MouseHelper]::Up()
}

switch ($Action) {
  'click'    { Click $X $Y; Write-Output "clicked $X,$Y" }
  'dblclick' {
    Click $X $Y; Start-Sleep -Milliseconds 80; Click $X $Y
    Write-Output "double-clicked $X,$Y"
  }
  'drag' {
    [MouseHelper]::SetCursorPos($X, $Y) | Out-Null
    Start-Sleep -Milliseconds 200
    [MouseHelper]::Down()
    Start-Sleep -Milliseconds 120
    $steps = [Math]::Max(10, [int]($DurMs / 16))
    for ($i = 1; $i -le $steps; $i++) {
      $nx = $X + [int](($X2 - $X) * $i / $steps)
      $ny = $Y + [int](($Y2 - $Y) * $i / $steps)
      [MouseHelper]::SetCursorPos($nx, $ny) | Out-Null
      Start-Sleep -Milliseconds 16
    }
    Start-Sleep -Milliseconds 120
    [MouseHelper]::Up()
    Write-Output "dragged $X,$Y -> $X2,$Y2"
  }
  default { Write-Output "unknown action: $Action"; exit 1 }
}
