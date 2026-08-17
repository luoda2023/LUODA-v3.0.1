$ErrorActionPreference = 'Stop'
try {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
  $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
  $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
  "types loaded" | Out-File 'J:\codex-work\LUODA-v3.0.1\ocr_out.txt'
} catch {
  "ERR1: $($_.Exception.Message)" | Out-File 'J:\codex-work\LUODA-v3.0.1\ocr_out.txt'
}
