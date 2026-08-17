if ($AutoTest) {
  $t = New-Object System.Windows.Forms.Timer
  $t.Add_Tick({ $t.Stop(); Confirm-Selection (New-Object System.Drawing.Rectangle(300, 200, 500, 400)) })
}
