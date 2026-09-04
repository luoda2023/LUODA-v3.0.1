from PIL import Image
im = Image.open('agent_memory/shots/emu_bottom.png').convert('RGB')
w,h = im.size
im.crop((0, 1550, w, h)).save('agent_memory/shots/emu_bottom_crop.png')
