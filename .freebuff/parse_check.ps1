$tokens = $null
$errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
  'J:\codex-work\LUODA-v3.0.1\flutter\assets\scripts\shot_overlay.ps1',
  [ref]$tokens,
  [ref]$errs)
if ($errs.Count -gt 0) {
  Write-Output ("ERRORS: " + $errs.Count)
  foreach ($e in $errs) {
    Write-Output ("line " + $e.Extent.StartLineNumber + " col " + $e.Extent.StartColumnNumber + ": " + $e.Message)
    Write-Output ("  text: " + $e.Extent.Text.Trim())
  }
} else {
  Write-Output "PARSE OK"
}
