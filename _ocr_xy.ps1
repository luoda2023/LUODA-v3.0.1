param([string]$ImgPath)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Storage.StorageFile, Windows.Foundation, ContentType=WindowsRuntime]
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($WinRtTask, $ResultType) {
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    $netTask.Result
}
Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Bitmap]::FromFile($ImgPath)
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($ImgPath)) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.SoftwareBitmap])
$bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$langs = [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages
$engine = $null
foreach ($l in $langs) { if ($l.LanguageTag -like 'zh*') { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($l); break } }
if (-not $engine) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
$result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
$scaleX = $img.Width / $decoder.PixelWidth
$scaleY = $img.Height / $decoder.PixelHeight
foreach ($line in $result.Lines) {
  $words = $line.Words
  if ($words.Count -gt 0) {
    $x0 = $words[0].BoundingRect.X * $scaleX
    $y0 = $words[0].BoundingRect.Y * $scaleY
    $x1 = $words[$words.Count-1].BoundingRect.X * $scaleX
    $y1 = $words[$words.Count-1].BoundingRect.Y * $scaleY
    $w = ($words[$words.Count-1].BoundingRect.X + $words[$words.Count-1].BoundingRect.Width) * $scaleX - $x0
    $h = ($words[0].BoundingRect.Height) * $scaleY
    "{0,4},{1,4} {2,4}x{3,4}  {4}" -f [int]$x0,[int]$y0,[int]$w,[int]$h,$line.Text
  }
}
$img.Dispose()
