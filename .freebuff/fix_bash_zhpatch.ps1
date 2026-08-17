$ErrorActionPreference = 'Stop'
$p = 'C:\Users\Administrator\AppData\Local\Programs\@codebufffreebuff-desktop\resources\orchestrator\orchestrator.js'
$c = [System.IO.File]::ReadAllText($p)

$bs = [string][char]0x5C   # backslash
$zh = $bs + 'u4e8c' + $bs + 'u8fdb' + $bs + 'u5236'   # literal \u4e8c\u8fdb\u5236

$before = ([regex]::Matches($c, [regex]::Escape($zh))).Count
Write-Output ("zh occurrences before: {0}" -f $before)

$oldJoinRoot = 'join(root, "' + $zh + '", "bash.exe")'
$oldJoinDir  = 'join(path18.dirname(dir), "' + $zh + '", "bash.exe")'
$oldJoinDir2 = 'join(path18.dirname(path18.dirname(dir)), "' + $zh + '", "bash.exe")'

$n1 = ([regex]::Matches($c, [regex]::Escape($oldJoinRoot))).Count
$c = $c.Replace($oldJoinRoot, 'join(root, "bin", "bash.exe")')
$n2 = ([regex]::Matches($c, [regex]::Escape($oldJoinDir))).Count
$c = $c.Replace($oldJoinDir, 'join(path18.dirname(dir), "bin", "bash.exe")')
$n3 = ([regex]::Matches($c, [regex]::Escape($oldJoinDir2))).Count
$c = $c.Replace($oldJoinDir2, 'join(path18.dirname(path18.dirname(dir)), "bin", "bash.exe")')
$total = $n1 + $n2 + $n3

Write-Output ("join(root) replaced: {0}" -f $n1)
Write-Output ("join(dir) replaced: {0}" -f $n2)
Write-Output ("join(dir2) replaced: {0}" -f $n3)

$after = ([regex]::Matches($c, [regex]::Escape($zh))).Count
$left = ([regex]::Matches($c, 'join\([^)]*' + $zh + '[^)]*bash')).Count
Write-Output ("zh occurrences after: {0}" -f $after)
Write-Output ("leftover zh in bash paths: {0}" -f $left)

# Sanity: we replaced exactly the 4 bash-path occurrences.
# Before count must be 6 (4 bash + 2 normal labels), after must be 2 (normal labels only).
if ($total -ne 4) { throw ("Expected 4 replacements, got {0} - aborting" -f $total) }
if ($left -ne 0) { throw "STILL zh literal in bash paths, aborting" }
if ($before -ne ($after + 4)) { throw ("Count mismatch before={0} after={1} - aborting" -f $before, $after) }
if ($after -lt 1) { Write-Output "WARN: no zh left at all (normal labels also replaced?)" }

$bak = $p + '.bak-bashfix'
if (-not (Test-Path $bak)) { Copy-Item $p $bak }
[System.IO.File]::WriteAllText($p, $c, (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("written OK, total replaced: {0}" -f $total)
