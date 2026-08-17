$ErrorActionPreference = "Stop"
try {
  $d = Get-Content 'J:\codex-work\LUODA-v3.0.1\ocr_screen2x.ps1' -Raw
  Invoke-Expression $d
} catch {
  Write-Host ("EXC: " + $_.Exception.ToString())
  if ($_.Exception.InnerException) { Write-Host ("INNER: " + $_.Exception.InnerException.ToString()) }
}
