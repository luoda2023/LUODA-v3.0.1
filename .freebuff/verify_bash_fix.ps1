$ErrorActionPreference = 'Continue'
$p = 'C:\Users\Administrator\AppData\Local\Programs\@codebufffreebuff-desktop\resources\orchestrator\orchestrator.js'
$c = [System.IO.File]::ReadAllText($p)
$bs = [string][char]0x5C
$zh = $bs + 'u4e8c' + $bs + 'u8fdb' + $bs + 'u5236'
$ok = ([regex]::Matches($c, 'join\([^)]*' + $zh + '[^)]*bash')).Count
$bin = ([regex]::Matches($c, 'join\([^)]*"bin"[^)]*bash')).Count
Write-Output ("zh in bash paths: {0}" -f $ok)
Write-Output ("bin in bash paths: {0}" -f $bin)
Write-Output ("bash.exe total: {0}" -f ([regex]::Matches($c, 'bash\.exe')).Count)
if (Test-Path ($p + '.bak-bashfix')) { Write-Output "backup exists: OK" } else { Write-Output "backup missing" }
