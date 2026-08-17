Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$p = Get-Process luoda -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Write-Output "NO_PROCESS"; exit }
$root = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$el = $walker.GetFirstChild($root)
$count = 0
while ($el -and $count -lt 400) {
  $name = $el.Current.Name
  $type = $el.Current.ControlType.ProgrammaticName
  if ($name -and $name.Trim().Length -gt 0) {
    Write-Output "[$type] $name"
  }
  $el = $walker.GetNextSibling($el)
  $count++
}
