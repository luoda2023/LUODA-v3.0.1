$ErrorActionPreference = 'Stop'
function ReplaceOnce($path, $old, $new) {
  $content = [System.IO.File]::ReadAllText($path)
  $idx = $content.IndexOf($old)
  if ($idx -lt 0) { throw "PATTERN NOT FOUND" }
  if ($content.IndexOf($old, $idx + 1) -ge 0) { throw "PATTERN NOT UNIQUE" }
  $content = $content.Substring(0, $idx) + $new + $content.Substring($idx + $old.Length)
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $content, $utf8)
  Write-Output "OK"
}
$p = 'J:\codex-work\LUODA-v3.0.1\flutter\lib\mobile\pages\home_page.dart'
$old = "          color: theme.dividerColor.withOpacity(0.45),"
$new = "          color: theme.dividerColor.withOpacity(0.5),"
ReplaceOnce $p $old $new