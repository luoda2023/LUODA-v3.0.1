param([string]$File, [int]$Start = 1, [int]$End = -1)
$c = Get-Content $File
if ($End -lt 0) { $End = $c.Length }
for ($i = $Start; $i -le $End -and $i -lt $c.Length; $i++) {
  '{0}: {1}' -f ($i + 1), $c[$i]
}
