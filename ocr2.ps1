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
    "D:\Personal\Temp\codex-clipboard-32b17515-2276-4876-8a71-1e01bf3bac3b.png",
    "D:\Personal\Temp\codex-clipboard-0b1551a0-22e4-4433-b4ba-6ae4552a2168.png",
    "D:\Personal\Temp\codex-clipboard-0b1c2c7a-f607-40e8-b450-2da16d82a5f4.png",
    "D:\Personal\Temp\codex-clipboard-70d3b0cd-9a2c-4a3c-bbad-c431a4540a6c.png",
    "D:\Personal\Temp\codex-clipboard-a8c5e694-dd23-4d3a-a47c-6c9911585700.png",
    "D:\Personal\Temp\codex-clipboard-60e94896-b662-4055-af4f-80ab74b7bad8.png",
    "D:\Personal\Temp\codex-clipboard-1a3a6950-b78e-4f35-a60c-017c7db37631.png"
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
$out | Out-File -FilePath "J:\codex-work\LUODA-v3.0.1\ocr_out2.txt" -Encoding utf8
Write-Host "done"
