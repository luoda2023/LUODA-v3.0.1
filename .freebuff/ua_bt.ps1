Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$proc = Get-Process -Id 20180 -ErrorAction SilentlyContinue
if (-not $proc) { Write-Host "no process"; exit }
$root = [System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)
$condition = [System.Windows.Automation.Condition]::TrueCondition
$all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
Write-Host ("nodes: " + $all.Count)
for ($i = 0; $i -lt $all.Count; $i++) {
  $el = $all.Item($i)
  $name = $el.Current.Name
  $type = $el.Current.ControlType.ProgrammaticName
  $rect = $el.Current.BoundingRectangle
  if ($name -match "蓝牙|Bluetooth|扫描|Scan" -or $type -match "Button") {
    Write-Host ("[{0}] {1} NAME={2} RECT={3},{4},{5},{6}" -f $i, $type, $name, [int]$rect.X, [int]$rect.Y, [int]$rect.Right, [int]$rect.Bottom)
  }
}
