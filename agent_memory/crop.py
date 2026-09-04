from PIL import Image
im = Image.open('agent_memory/shots/real_chat2.png').convert('RGB')
w,h = im.size
im.crop((0, 1500, w, h)).save('agent_memory/shots/real_chat2_bottom.png')
