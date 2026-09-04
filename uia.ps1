Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]56953654)
$cond=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,'*')
$items=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$cond)
Write-Output "total elements with name: $($items.Count)"
$i=0
foreach($e in $items){
  $i++
  if($i -gt 60){break}
  $name=$e.Current.Name; $type=$e.Current.ControlType.ProgrammaticName
  Write-Output ("{0}: [{1}] '{2}'" -f $i,$type,$name)
}
