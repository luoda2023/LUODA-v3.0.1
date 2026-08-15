<#
.SYNOPSIS
  Full-screen region-selection overlay (WeChat/Snipaste style) for the chat
  screenshot tool. The live desktop is dimmed, the user drags a rectangle
  (or holds Ctrl to auto-pick a window), and ONLY the selected region is
  captured and saved as PNG.

.USAGE
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File shot_overlay.ps1 -Out <png path> [-AutoTest]

  Exit code 0 with "OK" line -> selection captured.
  Exit code 1 -> user cancelled (Esc) or failure.
#>
param([string]$Out = "", [switch]$AutoTest)

$ErrorActionPreference = 'Stop'

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ShotNative {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  public struct POINT { public int X, Y; }
  public struct RECT { public int L, T, R, B; }
}
'@

# DPI-aware: all coordinates are physical pixels, consistent between the
# overlay forms, mouse events and CopyFromScreen.
[ShotNative]::SetProcessDPIAware() | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:logPath = Join-Path $env:TEMP ("shot_overlay_{0}.log" -f $PID)
function Write-Log([string]$msg) {
  try {
    Add-Content -Path $script:logPath -Value ((Get-Date -Format 'HH:mm:ss') + " " + $msg) -Encoding UTF8
  } catch { }
}

# Never show a JIT / unhandled-exception dialog: log and exit quietly instead.
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({
  param($sender, $e)
  try { Write-Log ("ThreadException: " + $e.Exception) } catch { }
  [Environment]::Exit(2)
})
[AppDomain]::CurrentDomain.add_UnhandledException({
  param($sender, $e)
  try { Write-Log ("UnhandledException: " + $e.ExceptionObject) } catch { }
  [Environment]::Exit(2)
})

# Brand green of the app + a magenta key color for the transparent draw form.
$BrandGreen = [System.Drawing.Color]::FromArgb(255, 7, 193, 96)
$KeyColor   = [System.Drawing.Color]::FromArgb(255, 255, 0, 255)

$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$vsX = $vs.X; $vsY = $vs.Y; $vsW = $vs.Width; $vsH = $vs.Height

# --- Shared state -------------------------------------------------------------
$script:start = $null      # drag start (vs-relative)
$script:end = $null        # drag end
$script:ctrlMode = $false  # Ctrl held -> pick-a-window mode
$script:hoverWin = $null   # highlighted window rect (vs-relative)
$script:active = $false    # left button down
$script:done = $false
$script:confirmed = $false # selection confirmed (vs cancelled)
$script:mouse = $null      # last mouse pos (vs-relative)

# --- Green cross cursor (bigger: 40px, 4px thick, brand green) -----------------
function New-GreenCrossCursor {
  $bmp = New-Object System.Drawing.Bitmap(40, 40, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
  try {
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
      $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
      $pen = New-Object System.Drawing.Pen($BrandGreen, 4)
      try {
        $g.DrawLine($pen, 20, 3, 20, 13)
        $g.DrawLine($pen, 20, 27, 20, 37)
        $g.DrawLine($pen, 3, 20, 13, 20)
        $g.DrawLine($pen, 27, 20, 37, 20)
      } finally { $pen.Dispose() }
    } finally {
      $g.Dispose()
    }
    $hIcon = $bmp.GetHicon()
    return New-Object System.Windows.Forms.Cursor($hIcon)
  } finally {
    $bmp.Dispose()
  }
}

# --- Dim forms: 4 plain-Opacity black forms whose union is the whole virtual
#     screen MINUS the selection. No Region is ever set on them (Opacity +
#     Region on layered windows is the known cause of the "screen goes black"
#     bug), so they are 100% reliable.
$script:masks = @()
for ($i = 0; $i -lt 4; $i++) {
  $m = New-Object System.Windows.Forms.Form
  $m.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
  $m.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
  $m.TopMost = $true
  $m.ShowInTaskbar = $false
  $m.BackColor = [System.Drawing.Color]::Black
  $m.Opacity = 0.45
  $script:masks += $m
}
$base = $script:masks[0]   # full screen initially; owns all mouse events
$base.Bounds = $vs
$base.Cursor = New-GreenCrossCursor

# --- Draw form: fully transparent (magenta + TransparencyKey), a Region that
#     punches a hole over the selection, OnPaint draws the cross / frame /
#     size label. It is NOT a layered-by-Opacity window, so its Region is
#     reliable.
$draw = New-Object System.Windows.Forms.Form
$draw.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$draw.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$draw.Bounds = $vs
$draw.TopMost = $true
$draw.ShowInTaskbar = $false
$draw.BackColor = $KeyColor
$draw.TransparencyKey = $KeyColor
$draw.Cursor = New-GreenCrossCursor

# --- Selection helpers ---------------------------------------------------------
function Get-SelRect {
  if ($script:start -and $script:end) {
    $x1 = [Math]::Min($script:start.X, $script:end.X)
    $y1 = [Math]::Min($script:start.Y, $script:end.Y)
    $x2 = [Math]::Max($script:start.X, $script:end.X)
    $y2 = [Math]::Max($script:start.Y, $script:end.Y)
    if (($x2 - $x1) -gt 2 -and ($y2 - $y1) -gt 2) {
      return New-Object System.Drawing.Rectangle($x1, $y1, ($x2 - $x1), ($y2 - $y1))
    }
  }
  return $null
}

function Update-Mask {
  try {
    $sel = $null
    if ($script:ctrlMode -and $script:hoverWin) { $sel = $script:hoverWin }
    else { $sel = Get-SelRect }

    if ($sel) {
      $sx = $sel.X; $sy = $sel.Y; $sw = $sel.Width; $sh = $sel.Height
      $base.SetBounds($vsX, $vsY, $sx, $vsH)
      $script:masks[1].SetBounds($vsX + $sx + $sw, $vsY, [Math]::Max(0, $vsW - $sx - $sw), $vsH)
      $script:masks[2].SetBounds($vsX + $sx, $vsY, $sw, $sy)
      $script:masks[3].SetBounds($vsX + $sx, $vsY + $sy + $sh, $sw, [Math]::Max(0, $vsH - $sy - $sh))
      for ($i = 1; $i -lt 4; $i++) {
        if (-not $script:masks[$i].Visible) { $script:masks[$i].Show() }
      }
    } else {
      $base.SetBounds($vsX, $vsY, $vsW, $vsH)
      for ($i = 1; $i -lt 4; $i++) {
        if ($script:masks[$i].Visible) { $script:masks[$i].Hide() }
      }
    }

    # Draw form region: whole screen minus the selection (plain window, its
    # Region is reliable). The punched area shows the desktop clearly.
    $reg = New-Object System.Drawing.Region((New-Object System.Drawing.Rectangle(0, 0, $vsW, $vsH)))
    if ($sel) { $reg.Exclude($sel) }
    $draw.Region = $reg
    $reg.Dispose()
    $draw.BringToFront()
    $draw.Invalidate()
  } catch {
    Write-Log ("Update-Mask: " + $_.Exception.Message)
  }
}

# --- Paint: big brand-green cross, green selection frame, size label -----------
$draw.Add_Paint({ param($s, $e)
  try {
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    # Full-screen cross lines following the mouse (brand green, 2px).
    if ($script:mouse) {
      $mx = $script:mouse.X; $my = $script:mouse.Y
      $cross = New-Object System.Drawing.Pen($BrandGreen, 2)
      try {
        $g.DrawLine($cross, $mx, 0, $mx, $vsH)
        $g.DrawLine($cross, 0, $my, $vsW, $my)
      } finally { $cross.Dispose() }
    }

    $sel = $null
    if ($script:ctrlMode -and $script:hoverWin) { $sel = $script:hoverWin }
    else { $sel = Get-SelRect }

    if ($sel) {
      $frame = New-Object System.Drawing.Pen($BrandGreen, 2)
      try {
        $g.DrawRectangle($frame, $sel.X, $sel.Y, $sel.Width, $sel.Height)
      } finally { $frame.Dispose() }

      if (-not $script:ctrlMode) {
        # Size label follows the selection's BOTTOM-RIGHT corner (Snipaste /
        # WeChat style) instead of being pinned to the top-left.
        $label = ("{0} x {1}" -f $sel.Width, $sel.Height)
        $font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
        try {
          $sz = $g.MeasureString($label, $font)
          $lx = $sel.Right - $sz.Width - 14
          $ly = $sel.Bottom + 10
          # Keep the label on-screen: flip above the selection if it would
          # overflow the bottom edge.
          if (($ly + $sz.Height + 8) -gt $vsH) { $ly = $sel.Top - $sz.Height - 10 }
          if ($lx -lt 2) { $lx = $sel.Left + 4 }
          if ($ly -lt 2) { $ly = $sel.Top + 4 }
          $bg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(210, 0, 0, 0))
          try {
            $g.FillRectangle($bg, $lx, $ly, ($sz.Width + 12), ($sz.Height + 6))
          } finally { $bg.Dispose() }
          $g.DrawString($label, $font, [System.Drawing.Brushes]::White, ($lx + 6), ($ly + 3))
        } finally { $font.Dispose() }
      }
    } else {
      # No selection yet: draw a top-center hint bar (dimmable so it is easy
      # for first-time users to understand what to do).
      $hint = "按住左键拖拽框选截图区域 · 按住 Ctrl 自动选择窗口 · Esc 取消"
      $hFont = New-Object System.Drawing.Font("Microsoft YaHei UI", 12, [System.Drawing.FontStyle]::Bold)
      try {
        $hSz = $g.MeasureString($hint, $hFont)
        $hx = [int](($vsW - $hSz.Width) / 2) - 18
        $hy = 34
        $hBg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(215, 20, 20, 20))
        try {
          $g.FillRectangle($hBg, $hx, $hy, ($hSz.Width + 36), ($hSz.Height + 16))
          $g.DrawString($hint, $hFont, [System.Drawing.Brushes]::White, ($hx + 18), ($hy + 8))
        } finally { $hBg.Dispose() }
      } finally { $hFont.Dispose() }
    }
  } catch {
    Write-Log ("Paint: " + $_.Exception.Message)
  }
})

# --- Window enumeration (Ctrl pick mode) ---------------------------------------
function Find-TopWindow([int]$screenX, [int]$screenY) {
  $pt = New-Object ShotNative+POINT
  $pt.X = $screenX; $pt.Y = $screenY
  $h = [ShotNative]::WindowFromPoint($pt)
  if ($h -eq [IntPtr]::Zero) { return $null }
  $root = [ShotNative]::GetAncestor($h, 2)  # GA_ROOT
  if ($root -eq [IntPtr]::Zero) { $root = $h }
  # Ignore our own overlay windows.
  foreach ($m in $script:masks) {
    if ($m.Handle -ne [IntPtr]::Zero -and $root -eq $m.Handle) { return $null }
  }
  if ($draw.Handle -ne [IntPtr]::Zero -and $root -eq $draw.Handle) { return $null }
  $r = New-Object ShotNative+RECT
  [ShotNative]::GetWindowRect($root, [ref]$r) | Out-Null
  if (($r.R - $r.L) -lt 40 -or ($r.B - $r.T) -lt 24) { return $null }
  if (-not [ShotNative]::IsWindowVisible($root)) { return $null }
  return $root
}

function Get-WindowRectForm([IntPtr]$h) {
  $r = New-Object ShotNative+RECT
  [ShotNative]::GetWindowRect($h, [ref]$r) | Out-Null
  return New-Object System.Drawing.Rectangle(($r.L - $vsX), ($r.T - $vsY), ($r.R - $r.L), ($r.B - $r.T))
}

# --- Mouse / keyboard events -------------------------------------------------
# IMPORTANT: the transparent draw form covers the whole screen and (until a
# selection exists) its Region is the full virtual screen, so EVERY mouse click
# lands on $draw — NOT on $base.  That was the bug that made dragging
# impossible: $draw had no handlers, so all input vanished.
# Fix: bind the SAME handlers to every form ($base, the 3 other masks and
# $draw), and translate coordinates with each form's own Bounds so the shared
# logic always works in virtual-screen coordinates.
function Get-VsPoint($f, [System.Windows.Forms.MouseEventArgs]$e) {
  New-Object System.Drawing.Point (($f.Bounds.X + $e.X) - $vsX), (($f.Bounds.Y + $e.Y) - $vsY)
}

# Core drag logic, extracted so both the real event handlers and the
# AutoTest harness exercise exactly the same code path.
function Handle-MouseDown([System.Drawing.Point]$pt) {
  $script:active = $true
  $script:mouse = $pt
  if ($script:ctrlMode) {
    $h = Find-TopWindow ($pt.X + $vsX) ($pt.Y + $vsY)
    if ($h) {
      $script:hoverWin = Get-WindowRectForm $h
      Update-Mask
      Confirm-Selection $script:hoverWin
    }
    return
  }
  $script:start = $pt
  $script:end = $pt
  Update-Mask
}

function Handle-MouseMove([System.Drawing.Point]$pt) {
  if ($script:done) { return }
  $script:mouse = $pt
  if ($script:ctrlMode) {
    $h = Find-TopWindow ($pt.X + $vsX) ($pt.Y + $vsY)
    $rect = if ($h) { Get-WindowRectForm $h } else { $null }
    $changed = $false
    if ($rect -and -not $script:hoverWin) { $changed = $true }
    elseif (-not $rect -and $script:hoverWin) { $changed = $true }
    elseif ($rect -and $script:hoverWin -and ($rect.X -ne $script:hoverWin.X -or $rect.Y -ne $script:hoverWin.Y -or $rect.Width -ne $script:hoverWin.Width -or $rect.Height -ne $script:hoverWin.Height)) { $changed = $true }
    if ($changed) {
      $script:hoverWin = $rect
      Update-Mask
    } else {
      $draw.Invalidate()
    }
    return
  }
  if ($script:active -and $script:start) {
    $script:end = $pt
    Update-Mask
  } else {
    $draw.Invalidate()
  }
}

function Handle-MouseUp() {
  $script:active = $false
  if ($script:ctrlMode) { return }
  $sel = Get-SelRect
  if ($sel -and $sel.Width -gt 8 -and $sel.Height -gt 8) {
    Confirm-Selection $sel
  } else {
    $script:start = $null; $script:end = $null
    Update-Mask
  }
}

function Add-ShotEvents($f) {
  $f.Add_MouseDown({
    param($s, $e)
    try {
      if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
      $s.Capture = $true
      Handle-MouseDown (Get-VsPoint $s $e)
    } catch {
      Write-Log ("MouseDown: " + $_.Exception.Message)
    }
  })

  $f.Add_MouseMove({
    param($s, $e)
    try {
      Handle-MouseMove (Get-VsPoint $s $e)
    } catch {
      Write-Log ("MouseMove: " + $_.Exception.Message)
    }
  })

  $f.Add_MouseUp({
    param($s, $e)
    try {
      if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
      $s.Capture = $false
      Handle-MouseUp
    } catch {
      Write-Log ("MouseUp: " + $_.Exception.Message)
    }
  })

  $f.Add_KeyDown({
    param($s, $e)
    try {
      if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $script:done = $true
        $script:confirmed = $false
        $f.Close()
        return
      }
      if ($e.KeyCode -eq [System.Windows.Forms.Keys]::ControlKey -or $e.KeyCode -eq [System.Windows.Forms.Keys]::LControlKey -or $e.KeyCode -eq [System.Windows.Forms.Keys]::RControlKey) {
        if (-not $script:ctrlMode) {
          $script:ctrlMode = $true
          $script:start = $null; $script:end = $null
          Update-Mask
        }
        $e.SuppressKeyPress = $true
      }
    } catch {
      Write-Log ("KeyDown: " + $_.Exception.Message)
    }
  })

  $f.Add_KeyUp({
    param($s, $e)
    try {
      if ($e.KeyCode -eq [System.Windows.Forms.Keys]::ControlKey -or $e.KeyCode -eq [System.Windows.Forms.Keys]::LControlKey -or $e.KeyCode -eq [System.Windows.Forms.Keys]::RControlKey) {
        if ($script:ctrlMode) {
          $script:ctrlMode = $false
          $script:hoverWin = $null
          Update-Mask
        }
        $e.SuppressKeyPress = $true
      }
    } catch {
      Write-Log ("KeyUp: " + $_.Exception.Message)
    }
  })
}

# Bind to every form so clicks anywhere on the virtual screen reach us.
Add-ShotEvents $base
for ($i = 1; $i -lt 4; $i++) { Add-ShotEvents $script:masks[$i] }
Add-ShotEvents $draw

# --- Confirmation --------------------------------------------------------------
function Confirm-Selection([System.Drawing.Rectangle]$region) {
  try {
    $script:done = $true
    $script:confirmed = $true
    # Hide ALL overlays first so the capture contains no mask / frame / cross.
    for ($i = 0; $i -lt 4; $i++) { $script:masks[$i].Hide() }
    $draw.Hide()
    Start-Sleep -Milliseconds 260
    $selX = $region.X + $vsX
    $selY = $region.Y + $vsY
    $selW = [Math]::Max(1, $region.Width)
    $selH = [Math]::Max(1, $region.Height)
    if (-not $Out) { $Out = Join-Path $env:TEMP ("shot_{0}.png" -f [DateTime]::Now.Ticks) }
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
    $base.Close()
  } catch {
    Write-Log ("Confirm: " + $_.Exception.Message)
    Write-Output ("FAIL " + $_.Exception.Message)
    [Environment]::Exit(2)
  }
}

# --- Run -----------------------------------------------------------------------
if ($AutoTest) {
  # Simulate a REAL drag: MouseDown at (300,200) then MouseMove through
  # several points (which exercises the shared Handle-* code path exactly
  # like a real user drag) then MouseUp at (800,600).
  try {
    $autoTimer = New-Object System.Windows.Forms.Timer
    $autoTimer.Interval = 700
    $autoTimer.Add_Tick({
      $autoTimer.Stop()
      try {
        Handle-MouseDown (New-Object System.Drawing.Point(300, 200))
        foreach ($step in @(@(400, 300), @(600, 450), @(800, 600))) {
          Start-Sleep -Milliseconds 60
          Handle-MouseMove (New-Object System.Drawing.Point($step[0], $step[1]))
        }
        Start-Sleep -Milliseconds 60
        Handle-MouseUp
        if (-not $script:confirmed) {
          Write-Output "FAIL no selection confirmed after simulated drag"
          [Environment]::Exit(2)
        }
      } catch {
        Write-Output ("FAIL " + $_.Exception.Message)
        [Environment]::Exit(2)
      }
    })
    $draw.Add_Shown({ param($s, $e) $autoTimer.Start() })
  } catch {
    Write-Log ("AutoTest setup: " + $_.Exception.Message)
    exit 1
  }
}

$base.Show()
$draw.Show()
$draw.Activate()
$draw.Focus()
Update-Mask

# Message pump until the base form is closed.
$null = [System.Windows.Forms.Application]::Run($base)
if (-not $script:confirmed) {
  Write-Output "CANCELLED"
  exit 1
}
exit 0
