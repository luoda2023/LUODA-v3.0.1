Get-Process -Name luoda -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "Killing PID $($_.Id)"
    Stop-Process -Id $_.Id -Force
}
Start-Sleep -Seconds 2
Get-Process -Name luoda -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "Still alive: PID $($_.Id)"
}
