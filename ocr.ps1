Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Storage.StorageFile, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Foundation, ContentType=WindowsRuntime]

function Await($WinRtTask, $ResultType) {
    $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
    $asTaskGeneric = $asTask.MakeGenericMethod($ResultType)
    $netTask = $asTaskGeneric.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    $netTask.Result
}

$lang = New-Object Windows.Globalization.Language("zh-CN")
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang)
if ($null -eq $engine) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }

$files = @(
    "D:\Personal\Temp\codex-clipboard-a5669333-9c4c-4426-b062-c2829025096f.png",
    "D:\Personal\Temp\codex-clipboard-80174ac8-3b87-48e9-85bd-0680bcd8ce12.png",
    "D:\Personal\Temp\codex-clipboard-ba462b68-5bab-4b42-9403-1037d1252977.png",
    "D:\Personal\Temp\codex-clipboard-f31f5dcb-8c4e-4f7a-a379-8062d9313d1d.jpg"
)
$out = New-Object System.Collections.ArrayList
foreach ($f in $files) {
    [void]$out.Add("===== $f =====")
    try {
        $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($f)) ([Windows.Storage.StorageFile])
        $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
        $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        $result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
        foreach ($line in $result.Lines) { [void]$out.Add($line.Text) }
    } catch {
        [void]$out.Add("ERROR: " + $_.Exception.Message)
    }
}
$out | Out-File -FilePath "J:\codex-work\LUODA-v3.0.1\ocr_out.txt" -Encoding utf8
Write-Host "done"
