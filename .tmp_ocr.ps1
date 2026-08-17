$winmd = 'C:\Program Files (x86)\Windows Kits\10\UnionMetadata\10.0.26100.0\Windows.winmd'
$rt = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\System.Runtime.WindowsRuntime.dll'
$cs = @'
using System;
using System.Text;
using System.Threading.Tasks;
using Windows.Storage;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Globalization;
public static class OcrHelper {
  public static string Run(string path) {
    return RunAsync(path).GetAwaiter().GetResult();
  }
  static async Task<string> RunAsync(string path) {
    var file = await StorageFile.GetFileFromPathAsync(path);
    using (var stream = await file.OpenReadAsync()) {
      var decoder = await BitmapDecoder.CreateAsync(stream);
      var bitmap = await decoder.GetSoftwareBitmapAsync();
      var engine = OcrEngine.TryCreateFromUserProfileLanguages();
      if (engine == null) engine = OcrEngine.TryCreateFromLanguage(new Language("zh-Hans-CN"));
      var result = await engine.RecognizeAsync(bitmap);
      var sb = new StringBuilder();
      foreach (var line in result.Lines) sb.AppendLine(line.Text);
      return sb.ToString();
    }
  }
}
'@
Add-Type -ReferencedAssemblies $winmd,$rt -TypeDefinition $cs -Language CSharp
[OcrHelper]::Run('D:\Personal\Temp\codex-clipboard-4d2ce2c0-view.png')
