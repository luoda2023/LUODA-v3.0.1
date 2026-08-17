$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, 23692)
$els = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
Write-Output "elements: $($els.Count)"
foreach ($el in $els) {
  Write-Output ("--- {0} | {1} | rect={2},{3},{4},{5}" -f $el.Current.ControlType.ProgrammaticName, $el.Current.Name, $el.Current.BoundingRectangle.X, $el.Current.BoundingRectangle.Y, $el.Current.BoundingRectangle.Width, $el.Current.BoundingRectangle.Height)
  if ($el.Current.ControlType.ProgrammaticName -match 'Window') {
    $kids = $el.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    Write-Output "  descendants: $($kids.Count)"
    $seen = @{}
    foreach ($k in $kids) {
      $n = $k.Current.Name
      $t = $k.Current.ControlType.ProgrammaticName
      $key = "$t|$n"
      if ($n -and -not $seen.ContainsKey($key)) {
        $seen[$key] = $true
        $r = $k.Current.BoundingRectangle
        Write-Output ("  {0} | {1} | rect={2},{3},{4},{5}" -f $t, $n, [int]$r.X, [int]$r.Y, [int]$r.Width, [int]$r.Height)
      }
    }
  }
}
