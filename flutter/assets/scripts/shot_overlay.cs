// shot_overlay.cs — WeChat/Snipaste-style full-screen region selection tool.
//
// Compiled at build time by csc.exe into shot_overlay.exe (a WinForms GUI
// app, no console window). It replaces the old PowerShell overlay script:
//   * starts in <100ms (no PowerShell startup / Add-Type JIT delay)
//   * never flashes a console window (winexe target)
//   * Chinese hint text is compiled from UTF-8 source (/codepage:65001),
//     so it can never turn into mojibake
//
// Flow: the live desktop is dimmed behind translucent masks, the user drags
// a rectangle (or holds Ctrl to auto-pick a window), and on release ONLY
// the selected region is captured to PNG. Exit code 0 = saved, 1 = cancelled.
//
// Usage: shot_overlay.exe -Out <png path>

using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace LuodaShot
{
    internal static class Native
    {
        [DllImport("user32.dll")]
        internal static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")]
        internal static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")]
        internal static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")]
        internal static extern IntPtr WindowFromPoint(POINT p);
        [DllImport("user32.dll")]
        internal static extern IntPtr GetAncestor(IntPtr h, uint flags);

        [StructLayout(LayoutKind.Sequential)]
        internal struct POINT { public int X; public int Y; }

        [StructLayout(LayoutKind.Sequential)]
        internal struct RECT { public int L; public int T; public int R; public int B; }
    }

    // Global keyboard filter so Esc / Ctrl are caught no matter which
    // overlay window currently has focus (including during a drag).
    internal sealed class KeyFilter : IMessageFilter
    {
        public bool PreFilterMessage(ref Message m)
        {
            if (m.Msg == 0x0100) // WM_KEYDOWN
            {
                Keys k = (Keys)((int)m.WParam & 0xFFFF);
                if (k == Keys.Escape) { Program.Cancel(); return true; }
                if (k == Keys.ControlKey || k == Keys.LControlKey || k == Keys.RControlKey)
                { Program.SetCtrlMode(true); return true; }
            }
            else if (m.Msg == 0x0101) // WM_KEYUP
            {
                Keys k = (Keys)((int)m.WParam & 0xFFFF);
                if (k == Keys.ControlKey || k == Keys.LControlKey || k == Keys.RControlKey)
                { Program.SetCtrlMode(false); return true; }
            }
            return false;
        }
    }

    internal static class Program
    {
        private const int KeyColorArgb = unchecked((int)0xFFFF00FF); // magenta transparency key
        private static readonly Color BrandGreen = Color.FromArgb(255, 7, 193, 96);

        private static string _outPath = "";
        private static int _vsX, _vsY, _vsW, _vsH;

        private static Form[] _masks;
        private static Form _baseForm;
        private static Form _draw;
        private static Cursor _cursor;

        private static bool _haveStart;
        private static Point _start;
        private static Point _end;
        private static bool _ctrlMode;
        private static bool _haveHover;
        private static Rectangle _hoverWin;
        private static bool _active;
        private static bool _done;
        private static bool _confirmed;
        private static bool _mouseSet;
        private static Point _mouse;

        [STAThread]
        private static int Main(string[] args)
        {
            bool autoTest = false;
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "-Out" && i + 1 < args.Length) _outPath = args[i + 1];
                if (args[i] == "-AutoTest") autoTest = true;
            }
            Native.SetProcessDPIAware();

            Rectangle vs = SystemInformation.VirtualScreen;
            _vsX = vs.X; _vsY = vs.Y; _vsW = vs.Width; _vsH = vs.Height;

            _cursor = CreateGreenCrossCursor();

            _masks = new Form[4];
            for (int i = 0; i < 4; i++)
            {
                Form m = new Form();
                m.FormBorderStyle = FormBorderStyle.None;
                m.StartPosition = FormStartPosition.Manual;
                m.TopMost = true;
                m.ShowInTaskbar = false;
                m.BackColor = Color.Black;
                m.Opacity = 0.45;
                _masks[i] = m;
            }
            _baseForm = _masks[0];
            _baseForm.Bounds = vs;
            _baseForm.Cursor = _cursor;

            _draw = new Form();
            _draw.FormBorderStyle = FormBorderStyle.None;
            _draw.StartPosition = FormStartPosition.Manual;
            _draw.Bounds = vs;
            _draw.TopMost = true;
            _draw.ShowInTaskbar = false;
            _draw.BackColor = Color.FromArgb(KeyColorArgb);
            _draw.TransparencyKey = Color.FromArgb(KeyColorArgb);
            _draw.Cursor = _cursor;
            _draw.Paint += OnPaint;

            foreach (Form f in _masks) BindEvents(f);
            BindEvents(_draw);

            Application.AddMessageFilter(new KeyFilter());

            if (autoTest)
            {
                // Simulate a REAL drag through the same Handle-* code path a
                // user exercises: down at (300,200), move through several
                // points, up at (800,600) -> selection confirmed -> PNG saved.
                System.Windows.Forms.Timer t = new System.Windows.Forms.Timer();
                t.Interval = 700;
                t.Tick += delegate(object s, EventArgs ev)
                {
                    t.Stop();
                    try
                    {
                        HandleMouseDown(new Point(300, 200));
                        Point[] steps = new Point[] {
                            new Point(400, 300), new Point(600, 450), new Point(800, 600)
                        };
                        foreach (Point p in steps)
                        {
                            System.Threading.Thread.Sleep(60);
                            HandleMouseMove(p);
                        }
                        System.Threading.Thread.Sleep(60);
                        HandleMouseUp();
                        if (!_confirmed)
                        {
                            _baseForm.Close();
                        }
                    }
                    catch (Exception ex)
                    {
                        Log("AutoTest: " + ex.Message);
                        _confirmed = false;
                        try { _baseForm.Close(); } catch { }
                    }
                };
                _draw.Shown += delegate(object s, EventArgs ev) { t.Start(); };
            }

            _baseForm.Show();
            _draw.Show();
            _draw.Activate();
            _draw.Focus();
            UpdateMask();

            Application.Run(_baseForm);
            return _confirmed ? 0 : 1;
        }

        // --- Public entry points used by the keyboard filter -----------------
        public static void Cancel()
        {
            if (_done) return;
            _done = true;
            _confirmed = false;
            try { _baseForm.Close(); } catch { }
        }

        public static void SetCtrlMode(bool on)
        {
            if (_done) return;
            _ctrlMode = on;
            if (on)
            {
                _haveStart = false;
                _haveHover = false;
            }
            else
            {
                _haveHover = false;
            }
            UpdateMask();
        }

        // --- Cursor ----------------------------------------------------------
        private static Cursor CreateGreenCrossCursor()
        {
            Bitmap bmp = new Bitmap(40, 40, PixelFormat.Format32bppPArgb);
            try
            {
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    using (Pen pen = new Pen(BrandGreen, 4))
                    {
                        g.DrawLine(pen, 20, 3, 20, 13);
                        g.DrawLine(pen, 20, 27, 20, 37);
                        g.DrawLine(pen, 3, 20, 13, 20);
                        g.DrawLine(pen, 27, 20, 37, 20);
                    }
                }
                IntPtr hIcon = bmp.GetHicon();
                return new Cursor(hIcon);
            }
            finally
            {
                bmp.Dispose();
            }
        }

        // --- Selection helpers ------------------------------------------------
        private static bool GetSelRect(out Rectangle r)
        {
            r = Rectangle.Empty;
            if (_haveStart)
            {
                int x1 = Math.Min(_start.X, _end.X);
                int y1 = Math.Min(_start.Y, _end.Y);
                int x2 = Math.Max(_start.X, _end.X);
                int y2 = Math.Max(_start.Y, _end.Y);
                if (x2 - x1 > 2 && y2 - y1 > 2)
                {
                    r = new Rectangle(x1, y1, x2 - x1, y2 - y1);
                    return true;
                }
            }
            return false;
        }

        private static void UpdateMask()
        {
            try
            {
                bool haveSel;
                Rectangle sel;
                if (_ctrlMode && _haveHover) { haveSel = true; sel = _hoverWin; }
                else haveSel = GetSelRect(out sel);

                if (haveSel)
                {
                    _baseForm.SetBounds(_vsX, _vsY, sel.X, _vsH);
                    _masks[1].SetBounds(_vsX + sel.X + sel.Width, _vsY,
                        Math.Max(0, _vsW - sel.X - sel.Width), _vsH);
                    _masks[2].SetBounds(_vsX + sel.X, _vsY, sel.Width, sel.Y);
                    _masks[3].SetBounds(_vsX + sel.X, _vsY + sel.Y + sel.Height,
                        sel.Width, Math.Max(0, _vsH - sel.Y - sel.Height));
                    for (int i = 1; i < 4; i++)
                    {
                        if (!_masks[i].Visible) _masks[i].Show();
                    }
                }
                else
                {
                    _baseForm.SetBounds(_vsX, _vsY, _vsW, _vsH);
                    for (int i = 1; i < 4; i++)
                    {
                        if (_masks[i].Visible) _masks[i].Hide();
                    }
                }

                // Draw-form region: whole screen minus the selection. The
                // Control.Region setter takes ownership of the new region and
                // disposes the previous one, so we must NOT dispose it here.
                Region reg = new Region(new Rectangle(0, 0, _vsW, _vsH));
                if (haveSel) reg.Exclude(sel);
                _draw.Region = reg;
                _draw.BringToFront();
                _draw.Invalidate();
            }
            catch (Exception ex)
            {
                Log("UpdateMask: " + ex.Message);
            }
        }

        // --- Painting ---------------------------------------------------------
        private static void OnPaint(object sender, PaintEventArgs e)
        {
            try
            {
                Graphics g = e.Graphics;
                g.SmoothingMode = SmoothingMode.AntiAlias;

                if (_mouseSet)
                {
                    using (Pen cross = new Pen(BrandGreen, 2))
                    {
                        g.DrawLine(cross, _mouse.X, 0, _mouse.X, _vsH);
                        g.DrawLine(cross, 0, _mouse.Y, _vsW, _mouse.Y);
                    }
                }

                bool haveSel;
                Rectangle sel;
                if (_ctrlMode && _haveHover) { haveSel = true; sel = _hoverWin; }
                else haveSel = GetSelRect(out sel);

                if (haveSel)
                {
                    using (Pen frame = new Pen(BrandGreen, 2))
                    {
                        g.DrawRectangle(frame, sel.X, sel.Y, sel.Width, sel.Height);
                    }

                    if (!_ctrlMode)
                    {
                        string label = sel.Width + " x " + sel.Height;
                        using (Font font = new Font("Segoe UI", 11, FontStyle.Bold))
                        {
                            SizeF sz = g.MeasureString(label, font);
                            float lx = sel.Right - sz.Width - 14;
                            float ly = sel.Bottom + 10;
                            if (ly + sz.Height + 8 > _vsH) ly = sel.Top - sz.Height - 10;
                            if (lx < 2) lx = sel.Left + 4;
                            if (ly < 2) ly = sel.Top + 4;
                            using (SolidBrush bg = new SolidBrush(Color.FromArgb(210, 0, 0, 0)))
                            {
                                g.FillRectangle(bg, lx, ly, sz.Width + 12, sz.Height + 6);
                            }
                            g.DrawString(label, font, Brushes.White, lx + 6, ly + 3);
                        }
                    }
                }
                else
                {
                    // Top-center hint bar so first-time users know what to do.
                    string hint = "按住左键拖拽框选截图区域 · 按住 Ctrl 自动选择窗口 · Esc 取消";
                    using (Font hFont = new Font("Microsoft YaHei UI", 12, FontStyle.Bold))
                    {
                        SizeF hSz = g.MeasureString(hint, hFont);
                        float hx = (float)((_vsW - hSz.Width) / 2) - 18;
                        float hy = 34;
                        using (SolidBrush hBg = new SolidBrush(Color.FromArgb(215, 20, 20, 20)))
                        {
                            g.FillRectangle(hBg, hx, hy, hSz.Width + 36, hSz.Height + 16);
                        }
                        g.DrawString(hint, hFont, Brushes.White, hx + 18, hy + 8);
                    }
                }
            }
            catch (Exception ex)
            {
                Log("Paint: " + ex.Message);
            }
        }

        // --- Window enumeration (Ctrl pick-a-window mode) ---------------------
        private static IntPtr FindTopWindow(int screenX, int screenY)
        {
            Native.POINT pt;
            pt.X = screenX; pt.Y = screenY;
            IntPtr h = Native.WindowFromPoint(pt);
            if (h == IntPtr.Zero) return IntPtr.Zero;
            IntPtr root = Native.GetAncestor(h, 2); // GA_ROOT
            if (root == IntPtr.Zero) root = h;
            foreach (Form m in _masks)
            {
                if (m.Handle != IntPtr.Zero && root == m.Handle) return IntPtr.Zero;
            }
            if (_draw.Handle != IntPtr.Zero && root == _draw.Handle) return IntPtr.Zero;

            Native.RECT r;
            Native.GetWindowRect(root, out r);
            if (r.R - r.L < 40 || r.B - r.T < 24) return IntPtr.Zero;
            if (!Native.IsWindowVisible(root)) return IntPtr.Zero;
            return root;
        }

        private static Rectangle WindowRectForm(IntPtr h)
        {
            Native.RECT r;
            Native.GetWindowRect(h, out r);
            return new Rectangle(r.L - _vsX, r.T - _vsY, r.R - r.L, r.B - r.T);
        }

        // --- Mouse handling ---------------------------------------------------
        private static Point VsPoint(Form f, MouseEventArgs e)
        {
            return new Point((f.Bounds.X + e.X) - _vsX, (f.Bounds.Y + e.Y) - _vsY);
        }

        private static void HandleMouseDown(Point pt)
        {
            _active = true;
            _mouse = pt;
            _mouseSet = true;
            if (_ctrlMode)
            {
                IntPtr h = FindTopWindow(pt.X + _vsX, pt.Y + _vsY);
                if (h != IntPtr.Zero)
                {
                    _haveHover = true;
                    _hoverWin = WindowRectForm(h);
                    UpdateMask();
                    Confirm(_hoverWin);
                }
                return;
            }
            _haveStart = true;
            _start = pt;
            _end = pt;
            UpdateMask();
        }

        private static void HandleMouseMove(Point pt)
        {
            if (_done) return;
            _mouse = pt;
            _mouseSet = true;
            if (_ctrlMode)
            {
                IntPtr h = FindTopWindow(pt.X + _vsX, pt.Y + _vsY);
                Rectangle rect = (h != IntPtr.Zero) ? WindowRectForm(h) : Rectangle.Empty;
                bool changed = false;
                if (h != IntPtr.Zero && !_haveHover) changed = true;
                else if (h == IntPtr.Zero && _haveHover) changed = true;
                else if (h != IntPtr.Zero && _haveHover &&
                         (rect.X != _hoverWin.X || rect.Y != _hoverWin.Y ||
                          rect.Width != _hoverWin.Width || rect.Height != _hoverWin.Height))
                { changed = true; }
                if (changed)
                {
                    _haveHover = h != IntPtr.Zero;
                    _hoverWin = rect;
                    UpdateMask();
                }
                else
                {
                    _draw.Invalidate();
                }
                return;
            }
            if (_active && _haveStart)
            {
                _end = pt;
                UpdateMask();
            }
            else
            {
                _draw.Invalidate();
            }
        }

        private static void HandleMouseUp()
        {
            _active = false;
            if (_ctrlMode) return;
            Rectangle sel;
            if (GetSelRect(out sel) && sel.Width > 8 && sel.Height > 8)
            {
                Confirm(sel);
            }
            else
            {
                _haveStart = false;
                UpdateMask();
            }
        }

        private static void BindEvents(Form f)
        {
            f.MouseDown += delegate(object s, MouseEventArgs e)
            {
                try
                {
                    if (e.Button != MouseButtons.Left) return;
                    HandleMouseDown(VsPoint(f, e));
                }
                catch (Exception ex) { Log("MouseDown: " + ex.Message); }
            };

            f.MouseMove += delegate(object s, MouseEventArgs e)
            {
                try
                {
                    HandleMouseMove(VsPoint(f, e));
                }
                catch (Exception ex) { Log("MouseMove: " + ex.Message); }
            };

            f.MouseUp += delegate(object s, MouseEventArgs e)
            {
                try
                {
                    if (e.Button != MouseButtons.Left) return;
                    HandleMouseUp();
                }
                catch (Exception ex) { Log("MouseUp: " + ex.Message); }
            };
        }

        // --- Confirmation -----------------------------------------------------
        private static void Confirm(Rectangle region)
        {
            try
            {
                _done = true;
                _confirmed = true;
                foreach (Form m in _masks) m.Hide();
                _draw.Hide();
                System.Threading.Thread.Sleep(260);
                int sx = region.X + _vsX;
                int sy = region.Y + _vsY;
                int sw = Math.Max(1, region.Width);
                int sh = Math.Max(1, region.Height);
                if (string.IsNullOrEmpty(_outPath))
                {
                    _outPath = Path.Combine(Path.GetTempPath(), "shot_" + DateTime.Now.Ticks + ".png");
                }
                using (Bitmap bmp = new Bitmap(sw, sh, PixelFormat.Format32bppPArgb))
                {
                    using (Graphics g = Graphics.FromImage(bmp))
                    {
                        g.CopyFromScreen(sx, sy, 0, 0, bmp.Size, CopyPixelOperation.SourceCopy);
                    }
                    bmp.Save(_outPath, ImageFormat.Png);
                }
                _baseForm.Close();
            }
            catch (Exception ex)
            {
                Log("Confirm: " + ex.Message);
                _confirmed = false;
                try { _baseForm.Close(); } catch { }
            }
        }

        private static void Log(string msg)
        {
            try
            {
                string p = Path.Combine(Path.GetTempPath(), "shot_overlay_" + System.Diagnostics.Process.GetCurrentProcess().Id + ".log");
                File.AppendAllText(p, DateTime.Now.ToString("HH:mm:ss") + " " + msg + Environment.NewLine);
            }
            catch { }
        }
    }
}
