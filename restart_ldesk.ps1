$ErrorActionPreference = "Stop"
Stop-Process -Id 22196 -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 800
$env:LDESK_DEBUG_API = '1'
$env:LDESK_DEBUG_API_TOKEN = 'testtoken1234567890'
$proc = Start-Process -FilePath "J:\codex-work\LUODA-v3.0.1\flutter\build\windows\x64\runner\Release\LDesk.exe" -WorkingDirectory "J:\codex-work\LUODA-v3.0.1\flutter\build\windows\x64\runner\Release" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 6
Write-Host "PID=$($proc.Id)"
Get-NetTCPConnection -OwningProcess $proc.Id -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -ne 21118 } | Select-Object LocalAddress, LocalPort | Format-Table -AutoSize
Write-Host "TOKEN=$env:LDESK_DEBUG_API_TOKEN"
