$tokens = $null; $errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile('J:\codex-work\LUODA-v3.0.1\flutter\assets\scripts\shot_overlay.ps1', [ref]$tokens, [ref]$errs)
if ($errs.Count -gt 0) { "FAIL: " + $errs[0].Message + " line " + $errs[0].Extent.StartLineNumber } else { "PARSE OK" }
