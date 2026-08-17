param([string]$Out = "C:\Users\Administrator\AppData\Local\Temp\virt.png")
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$v = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap($v.Width, $v.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($v.Location, [System.Drawing.Point]::Empty, $v.Size)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "virtual=$($v.X),$($v.Y) $($v.Width)x$($v.Height)"
