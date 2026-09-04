from PIL import Image
im = Image.open('agent_memory/shots/emu_now_en2.png').convert('RGB')
w,h = im.size
im.resize((w//2, h//2)).save('agent_memory/shots/emu_en2_half.png')
