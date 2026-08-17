$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, 23692)
$app = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
if (-not $app) { Write-Output "no element for pid 23692"; exit }
function Dump($el, $depth) {
  $name = $el.Current.Name
  $type = $el.Current.ControlType.ProgrammaticName
  if ($name -or $type -match 'Button|Edit|Text|MenuItem') {
    Write-Output ("{0}{1} | {2}" -f ('  ' * $depth), $type, $name)
  }
  if ($depth -ge 12) { return }
  try {
    $children = $el.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($c in $children) { Dump $c ($depth + 1) }
  } catch {}
}
Dump $app 0
