import ctypes, subprocess, os
from ctypes import wintypes
user32 = ctypes.windll.user32
EnumWindows = user32.EnumWindows
EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
GetWindowThreadProcessId = user32.GetWindowThreadProcessId
IsWindowVisible = user32.IsWindowVisible
target_pid = 29172
results = []
def foreach(hwnd, lParam):
    pid = wintypes.DWORD()
    GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    if pid.value == target_pid and IsWindowVisible(hwnd):
        results.append(int(hwnd))
    return True
EnumWindows(EnumWindowsProc(foreach), None)
hwnd = results[0]
rect = wintypes.RECT()
user32.GetWindowRect(hwnd, ctypes.byref(rect))
out = 'C:/Program Files/LUODA/screenshot.png'
w = rect.right - rect.left; h = rect.bottom - rect.top
ps = ('Add-Type -AssemblyName System.Windows.Forms; '
      'Add-Type -AssemblyName System.Drawing; '
      f' = New-Object System.Drawing.Rectangle({rect.left},{rect.top},{w},{h}); '
      ' = New-Object System.Drawing.Bitmap(.Width, .Height); '
      ' = [System.Drawing.Graphics]::FromImage(); '
      '.CopyFromScreen(.Location, [System.Drawing.Point]::Empty, .Size); '
      f'.Save(\"' + out + '\", [System.Drawing.Imaging.ImageFormat]::Png); '
      '.Dispose(); .Dispose()')
with open(r'C:\Program Files\LUODA\_cap.ps1','w') as f:
    f.write(ps)
subprocess.run(['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File',r'C:\Program Files\LUODA\_cap.ps1'])
print('size:', os.path.getsize(out) if os.path.exists(out) else 'missing')
