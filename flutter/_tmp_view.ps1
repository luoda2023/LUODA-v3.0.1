param([int]$Start = 4190, [int]$End = 4256)
$c = Get-Content 'J:\codex-work\LUODA-v3.0.1\flutter\lib\models\chat_model.dart'
for ($i = $Start; $i -le $End -and $i -lt $c.Length; $i++) {
  '{0}: {1}' -f ($i + 1), $c[$i]
}
