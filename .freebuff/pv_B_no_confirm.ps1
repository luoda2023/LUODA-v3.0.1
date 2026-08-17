if ($AutoTest) {
  $t = New-Object System.Windows.Forms.Timer
  $t.Add_Tick({ $t.Stop() })
}
