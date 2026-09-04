# -*- coding: utf-8 -*-
import ctypes, time
from ctypes import wintypes
user32 = ctypes.windll.user32
h = 56953654
# get window rect
class RECT(ctypes.Structure):
    _fields_=[('left',ctypes.c_long),('top',ctypes.c_long),('right',ctypes.c_long),('bottom',ctypes.c_long)]
r=RECT()
user32.GetWindowRect(h, ctypes.byref(r))
print('rect', r.left, r.top, r.right, r.bottom, 'w=',r.right-r.left,'h=',r.bottom-r.top)
# bring to front
user32.ShowWindow(h, 9)
user32.SetForegroundWindow(h)
time.sleep(1)
# printscreen of that area via PIL ImageGrab
from PIL import ImageGrab
im=ImageGrab.grab(bbox=(r.left, r.top, r.right, r.bottom))
im.save('J:\\codex-work\\LUODA-v3.0.1\\_win_now.png')
print('saved', im.size)
