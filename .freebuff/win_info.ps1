Get-Process luoda -ErrorAction SilentlyContinue | ForEach-Object {
  if ($_.MainWindowHandle -ne 0) {
    Write-Output ("id=" + $_.Id + " hwnd=" + $_.MainWindowHandle + " title=[" + $_.MainWindowTitle + "]")
  }
}
