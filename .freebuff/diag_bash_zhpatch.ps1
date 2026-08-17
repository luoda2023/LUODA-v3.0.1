$ErrorActionPreference = 'Continue'
$p = 'C:\Users\Administrator\AppData\Local\Programs\@codebufffreebuff-desktop\resources\orchestrator\orchestrator.js'
$c = [System.IO.File]::ReadAllText($p)
Write-Output ("file length: {0}" -f $c.Length)

# find every occurrence of 'bash.exe' with 120 chars of context
$idx = 0
$count = 0
while (($idx = $c.IndexOf('bash.exe', $idx)) -ge 0) {
  $count++
  $start = [Math]::Max(0, $idx - 70)
  $len = [Math]::Min(120, $c.Length - $start)
  $seg = $c.Substring($start, $len)
  # dump as codepoints
  $cp = ($seg.ToCharArray() | ForEach-Object { 'U+{0:X4}' -f [int]$_ }) -join ' '
  Write-Output ("--- occurrence {0} at {1} ---" -f $count, $idx)
  Write-Output $seg
  Write-Output ("CODEPOINTS: " + $cp)
  $idx += 8
  if ($count -ge 6) { break }
}

# also check the 'binary' label line
$bi = $c.IndexOf('binary: [2')
if ($bi -ge 0) {
  $seg = $c.Substring($bi, [Math]::Min(60, $c.Length - $bi))
  $cp = ($seg.ToCharArray() | ForEach-Object { 'U+{0:X4}' -f [int]$_ }) -join ' '
  Write-Output "--- binary label ---"
  Write-Output $seg
  Write-Output ("CODEPOINTS: " + $cp)
}

# check file encoding: look for BOM
$bytes = [System.IO.File]::ReadAllBytes($p)
Write-Output ("first bytes: {0}" -f (($bytes[0..([Math]::Min(15, $bytes.Length-1))] | ForEach-Object { $_.ToString('X2') }) -join ' '))
