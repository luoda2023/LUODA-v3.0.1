param([string]$P = "")
if (-not $P) { $P = "J:\codex-work\LUODA-v3.0.1\flutter\assets\scripts\shot_overlay.ps1" }
$tokens = $null
$errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($P, [ref]$tokens, [ref]$errs)
if ($errs.Count -gt 0) {
  Write-Output ("FAIL line " + $errs[0].Extent.StartLineNumber + " col " + $errs[0].Extent.StartColumnNumber + ": " + $errs[0].Message)
} else {
  Write-Output "PARSE OK"
}
