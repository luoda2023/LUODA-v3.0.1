from PIL import Image
im = Image.open('agent_memory/shots/real_remote.png').convert('RGB')
w,h = im.size
im.crop((0, 0, w, 200)).save('agent_memory/shots/real_remote_top.png')
