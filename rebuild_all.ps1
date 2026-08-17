$ErrorActionPreference = 'Continue'
$log = 'J:\codex-work\LUODA-v3.0.1\.runtime\rebuild-20260807.log'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
"=== cargo build release flutter $(Get-Date -Format 'HH:mm:ss') ===" | Out-File $log
Push-Location 'J:\codex-work\LUODA-v3.0.1'
cargo build --release --features flutter 2>&1 | Tee-Object -FilePath $log -Append | Select-Object -Last 5
$cargoExit = $LASTEXITCODE
"cargo exit=$cargoExit after $([math]::Round($sw.Elapsed.TotalSeconds))s" | Out-File $log -Append
Pop-Location
if ($cargoExit -ne 0) { "CARGO FAILED" | Out-File $log -Append; exit 1 }
"=== flutter build windows $(Get-Date -Format 'HH:mm:ss') ===" | Out-File $log -Append
$env:Path = "J:\codex-work\flutter-sdk\flutter\bin;$env:Path"
Push-Location 'J:\codex-work\LUODA-v3.0.1\flutter'
flutter build windows --release 2>&1 | Tee-Object -FilePath $log -Append | Select-Object -Last 10
$flExit = $LASTEXITCODE
"flutter exit=$flExit after $([math]::Round($sw.Elapsed.TotalSeconds))s" | Out-File $log -Append
Pop-Location
Write-Output "DONE cargo=$cargoExit flutter=$flExit total=$([math]::Round($sw.Elapsed.TotalSeconds))s"
