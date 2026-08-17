# -*- coding: utf-8 -*-
from PIL import Image
im = Image.open(r'D:\Personal\Temp\codex-clipboard-ba462b68-5bab-4b42-9403-1037d1252977.png').convert('RGB')
print(im.size)
im.save(r'J:\codex-work\LUODA-v3.0.1\flutter\_tmp_ba.png')
