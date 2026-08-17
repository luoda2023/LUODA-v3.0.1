<#
.SYNOPSIS
  Full-screen selection overlay for the chat "screenshot" tool.

  Flow (WeChat-style): the user sees the live desktop dimmed behind a
  translucent mask, drags a rectangle (or holds Ctrl to auto-pick a window),
  and on release ONLY the selected region is captured and saved to a PNG.
  The app window may be moved off-screen by the caller beforehand so it does
  not appear in the capture.

.USAGE
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File shot_overlay.ps1 -Out <png path>

  Exit code 0 with "OK" line -> selection captured.
  Exit code 1 -> user cancelled (Esc) or failure.
#>
param([string]$Out = "", [switch]$AutoTest)

$ErrorActionPreference = 'Stop'

# --- Native helpers ---------------------------------------------------------
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class ShotNative {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
  [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr h);
  [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr h);
  [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr h, IntPtr o);
  [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr o);
  [DllImport("user32.dll")] public static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc, ref POINT pptSrc, uint crKey, ref BLENDFUNCTION pblend, uint dwFlags);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  public struct POINT { public int X, Y; }
  public struct SIZE { public int W, H; }
  public struct RECT { public int L, T, R, B; }
  public struct BLENDFUNCTION { public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat; }
}
'@

# DPI-aware so all coordinates are physical pixels (consistent across the
# overlay form, mouse events and CopyFromScreen).
[ShotNative]::SetProcessDPIAware() | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Virtual screen geometry ------------------------------------------------
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$vsX = $vs.X; $vsY = $vs.Y; $vsW = $vs.Width; $vsH = $vs.Height

# --- Overlay form ------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.Bounds = $vs
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.Cursor = [System.Windows.Forms.Cursors]::Cross
$form.BackColor = [System.Drawing.Color]::Black

# Add WS_EX_LAYERED via CreateParams override.
$script:layeredSet = $false
$form.Add_HandleCreated({ param($s, $e)
  if ($script:layeredSet) { return }
  $script:layeredSet = $true
  try { Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class StyleHelper {
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
  public const int GWL_EXSTYLE = -20;
  public const int WS_EX_LAYERED = 0x80000;
}
'@ } catch {}
  $ex = [StyleHelper]::GetWindowLong($form.Handle, [StyleHelper]::GWL_EXSTYLE)
  [StyleHelper]::SetWindowLong($form.Handle, [StyleHelper]::GWL_EXSTYLE, ($ex -bor [StyleHelper]::WS_EX_LAYERED)) | Out-Null
})

# --- State -------------------------------------------------------------------
$script:start = $null      # drag start (form coords)
$script:end = $null        # drag end
$script:ctrlMode = $false  # Ctrl held -> pick-a-window mode
$script:hoverWin = $null   # highlighted window rect in virtual-screen coords (physical)
$script:active = $false    # mouse button down
$script:done = $false
$script:confirmed = $false  # selection confirmed (vs cancelled)

# --- Mask rendering ----------------------------------------------------------
function Draw-Mask {
  $bmp = New-Object System.Drawing.Bitmap($vsW, $vsH, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
  try {
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
      $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
      # Whole screen dimmed 45%.
      $g.Clear([System.Drawing.Color]::FromArgb(115, 0, 0, 0))

      $sel = $null
      if ($script:ctrlMode -and $script:hoverWin) {
        # Window-pick mode: keep the hovered window fully visible.
        $sel = $script:hoverWin
      } elseif ($script:start -and $script:end) {
        $x1 = [Math]::Min($script:start.X, $script:end.X)
        $y1 = [Math]::Min($script:start.Y, $script:end.Y)
        $x2 = [Math]::Max($script:start.X, $script:end.X)
        $y2 = [Math]::Max($script:start.Y, $script:end.Y)
        if ($x2 - $x1 -gt 2 -and $y2 - $y1 -gt 2) {
          $sel = New-Object System.Drawing.Rectangle($x1, $y1, ($x2 - $x1), ($y2 - $y1))
        }
      }
      if ($sel) {
        # Punch a transparent hole (region stays fully visible).
        $g.FillRectangle([System.Drawing.Brushes]::Transparent, $sel)
        # Selection border.
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 7, 193, 96), 2)
        try { $g.DrawRectangle($pen, $sel) } finally { $pen.Dispose() }
        # Size label.
        if ($script:ctrlMode -eq $false -and $sel.Width -gt 20 -and $sel.Height -gt 16) {
          $label = ("{0} x {1}" -f $sel.Width, $sel.Height)
          $font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
          try {
            $sz = $g.MeasureString($label, $font)
            $lx = $sel.X + 4
            $ly = $sel.Y + 4
            $bg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 0, 0, 0))
            try {
              $g.FillRectangle($bg, $lx, $ly, ($sz.Width + 10), ($sz.Height + 4))
            } finally { $bg.Dispose() }
            $g.DrawString($label, $font, [System.Drawing.Brushes]::White, ($lx + 5), ($ly + 2))
          } finally { $font.Dispose() }
        }
      }
    } finally {
      $g.Dispose()
    }

    # Push per-pixel alpha mask through UpdateLayeredWindow.
    $hdcScreen = [ShotNative]::GetDC([IntPtr]::Zero)
    try {
      $memDC = [ShotNative]::CreateCompatibleDC($hdcScreen)
      try {
        $hBmp = $bmp.GetHbitmap([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
        try {
          $old = [ShotNative]::SelectObject($memDC, $hBmp)
          $ptDst = New-Object ShotNative+POINT
          $ptDst.X = $vsX; $ptDst.Y = $vsY
          $ptSrc = New-Object ShotNative+POINT
          $ptSrc.X = 0; $ptSrc.Y = 0
          $size = New-Object ShotNative+SIZE
          $size.W = $vsW; $size.H = $vsH
          $blend = New-Object ShotNative+BLENDFUNCTION
          $blend.BlendOp = 0; $blend.BlendFlags = 0
          $blend.SourceConstantAlpha = 255; $blend.AlphaFormat = 1
          [ShotNative]::UpdateLayeredWindow($form.Handle, $hdcScreen, [ref]$ptDst, [ref]$size, $memDC, [ref]$ptSrc, 0, [ref]$blend, 2) | Out-Null
          [ShotNative]::SelectObject($memDC, $old) | Out-Null
        } finally {
          [ShotNative]::DeleteObject($hBmp) | Out-Null
        }
      } finally {
        [ShotNative]::DeleteDC($memDC) | Out-Null
      }
    } finally {
      [ShotNative]::ReleaseDC([IntPtr]::Zero, $hdcScreen) | Out-Null
    }
  } finally {
    $bmp.Dispose()
  }
}

# --- Window enumeration (Ctrl pick mode) ------------------------------------
$script:windows = New-Object System.Collections.ArrayList
function Find-TopWindow([int]$screenX, [int]$screenY) {
  $pt = New-Object ShotNative+POINT
  $pt.X = $screenX; $pt.Y = $screenY
  $h = [ShotNative]::WindowFromPoint($pt)
  if ($h -eq [IntPtr]::Zero) { return $null }
  # Walk up to the root window.
  $root = [ShotNative]::GetAncestor($h, 2)  # GA_ROOT
  if ($root -eq [IntPtr]::Zero) { $root = $h }
  if ($root -eq $form.Handle) { return $null }  # never select ourselves
  # Verify it is a visible top-level window with a size.
  $r = New-Object ShotNative+RECT
  [ShotNative]::GetWindowRect($root, [ref]$r) | Out-Null
  if (($r.R - $r.L) -lt 40 -or ($r.B - $r.T) -lt 24) { return $null }
  if (-not [ShotNative]::IsWindowVisible($root)) { return $null }
  return $root
}

function Get-WindowRect([IntPtr]$h) {
  $r = New-Object ShotNative+RECT
  [ShotNative]::GetWindowRect($h, [ref]$r) | Out-Null
  return New-Object System.Drawing.Rectangle($r.L, $r.T, ($r.R - $r.L), ($r.B - $r.T))
}

# --- Mouse / keyboard events -------------------------------------------------
$form.Add_MouseDown({ param($s, $e)
  if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
  $script:active = $true
  if ($script:ctrlMode) {
    # Click -> select the window under the cursor.
    $h = Find-TopWindow ($e.X + $vsX) ($e.Y + $vsY)
    if ($h) {
      $r = Get-WindowRect $h
      # Convert to form (virtual-screen-relative) coordinates.
      $script:hoverWin = New-Object System.Drawing.Rectangle(($r.X - $vsX), ($r.Y - $vsY), $r.Width, $r.Height)
      Confirm-Selection $script:hoverWin
    }
    return
  }
  $script:start = $e.Location
  $script:end = $e.Location
  Draw-Mask
})

$form.Add_MouseMove({ param($s, $e)
  if ($script:done) { return }
  if ($script:ctrlMode) {
    $h = Find-TopWindow ($e.X + $vsX) ($e.Y + $vsY)
    $rect = if ($h) {
      $rr = Get-WindowRect $h
      New-Object System.Drawing.Rectangle(($rr.X - $vsX), ($rr.Y - $vsY), $rr.Width, $rr.Height)
    } else { $null }
    $changed = $false
    if ($rect -and -not $script:hoverWin) { $changed = $true }
    elseif (-not $rect -and $script:hoverWin) { $changed = $true }
    elseif ($rect -and $script:hoverWin -and ($rect.X -ne $script:hoverWin.X -or $rect.Y -ne $script:hoverWin.Y -or $rect.Width -ne $script:hoverWin.Width -or $rect.Height -ne $script:hoverWin.Height)) { $changed = $true }
    if ($changed) {
      $script:hoverWin = $rect
      Draw-Mask
    }
    return
  }
  if ($script:active -and $script:start) {
    $script:end = $e.Location
    Draw-Mask
  }
})

$form.Add_MouseUp({ param($s, $e)
  if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
  $script:active = $false
  if ($script:ctrlMode) { return }
  if ($script:start -and $script:end) {
    $x1 = [Math]::Min($script:start.X, $script:end.X)
    $y1 = [Math]::Min($script:start.Y, $script:end.Y)
    $x2 = [Math]::Max($script:start.X, $script:end.X)
    $y2 = [Math]::Max($script:start.Y, $script:end.Y)
    if (($x2 - $x1) -gt 8 -and ($y2 - $y1) -gt 8) {
      Confirm-Selection (New-Object System.Drawing.Rectangle($x1, $y1, ($x2 - $x1), ($y2 - $y1)))
    } else {
      $script:start = $null; $script:end = $null
      Draw-Mask
    }
  }
})

$form.Add_KeyDown({ param($s, $e)
  if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
    $script:done = $true
    $script:confirmed = $false
    $form.Close()
    return
  }
  if ($e.KeyCode -eq [System.Windows.Forms.Keys]::ControlKey -or $e.KeyCode -eq [System.Windows.Forms.Keys]::LControlKey -or $e.KeyCode -eq [System.Windows.Forms.Keys]::RControlKey) {
    if (-not $script:ctrlMode) {
      $script:ctrlMode = $true
      $script:start = $null; $script:end = $null
      Draw-Mask
    }
    $e.SuppressKeyPress = $true
  }
})

$form.Add_KeyUp({ param($s, $e)
  if ($e.KeyCode -eq [System.Windows.Forms.Keys]::ControlKey -or $e.KeyCode -eq [System.Windows.Forms.Keys]::LControlKey -or $e.KeyCode -eq [System.Windows.Forms.Keys]::RControlKey) {
    if ($script:ctrlMode) {
      $script:ctrlMode = $false
      $script:hoverWin = $null
      Draw-Mask
    }
    $e.SuppressKeyPress = $true
  }
})

# --- Confirmation ------------------------------------------------------------
function Confirm-Selection([System.Drawing.Rectangle]$region) {
  $script:done = $true
  $script:confirmed = $true
  # Hide the overlay first so the capture does not include the mask.
  $form.Hide()
  Start-Sleep -Milliseconds 220
  $selX = $region.X + $vsX
  $selY = $region.Y + $vsY
  $selW = [Math]::Max(1, $region.Width)
  $selH = [Math]::Max(1, $region.Height)
  if (-not $Out) { $Out = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ("shot_{0}.png" -f [DateTime]::Now.Ticks)) }
  $bmp = New-Object System.Drawing.Bitmap($selW, $selH, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
  try {
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
      $g.CopyFromScreen($selX, $selY, 0, 0, $bmp.Size, [System.Drawing.CopyPixelOperation]::SourceCopy)
    } finally {
      $g.Dispose()
    }
    $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $bmp.Dispose()
  }
  Write-Output ("OK {0} {1} {2} {3} -> {4}" -f $region.X, $region.Y, $selW, $selH, $Out)
  $form.Close()
}

# --- Run ---------------------------------------------------------------------
if ($AutoTest) {
  # 自动化自测：窗体显示后自动确认一个固定区域，验证
  # “遮罩 → 隐藏 → 区域截屏 → 保存 PNG → 退出”完整链路。
  try {
    $autoTimer = New-Object System.Windows.Forms.Timer
    if (-not $autoTimer) { Write-Output "AUTOTEST timer-null"; exit 1 }
    $autoTimer.Interval = 900
    $autoTimer.Add_Tick({
      $autoTimer.Stop()
      Confirm-Selection (New-Object System.Drawing.Rectangle(300, 200, 500, 400))
    })
    $form.Add_Shown({ param($s, $e) $autoTimer.Start() })
  } catch {
    Write-Output ("AUTOTEST fail: " + $_.Exception.Message)
    exit 1
  }
}
$form.Show()
$form.Activate()
Start-Sleep -Milliseconds 120
Draw-Mask

# Message pump until the form is closed.
$null = [System.Windows.Forms.Application]::Run($form)
if (-not $script:confirmed) {
  # Esc / window close without confirmation -> cancelled.
  Write-Output "CANCELLED"
  exit 1
}
exit 0