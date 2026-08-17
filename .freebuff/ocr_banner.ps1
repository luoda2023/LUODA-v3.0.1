Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$ErrorActionPreference = 'Stop'
$img = [System.Drawing.Image]::FromFile("J:\codex-work\LUODA-v3.0.1\.freebuff\banner_crop.png")
$bmp = New-Object System.Drawing.Bitmap $img
$bmp = $bmp.Clone((New-Object System.Drawing.Rectangle(0,0,$bmp.Width,$bmp.Height)),[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$rect = New-Object System.Drawing.Rectangle(0,0,$bmp.Width,$bmp.Height)
$data = $bmp.LockBits($rect,[System.Drawing.Imaging.ImageLockMode]::ReadOnly,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$bytes = New-Object byte[] ($data.Stride * $data.Height)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0,$bytes,0,$bytes.Length)
$bmp.UnlockBits($data)
$stream = New-Object System.IO.MemoryStream
$bmp.Save($stream,[System.Drawing.Imaging.ImageFormat]::Png)
$stream.Position = 0
[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics,ContentType=WindowsRuntime] | Out-Null
$ras = [Windows.Storage.Streams.RandomAccessStream]::CreateOverRandomAccessStream($stream)
$decoder = [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($ras)
$op = $decoder.GetAwaiter().GetResult()
$bitmap = $op.GetSoftwareBitmapAsync().GetAwaiter().GetResult()
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
$result = $engine.RecognizeAsync($bitmap).GetAwaiter().GetResult()
foreach ($line in $result.Lines) { Write-Output $line.Text }
