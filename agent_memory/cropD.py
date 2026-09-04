from PIL import Image
im = Image.open('agent_memory/shots/real_top.png').convert('RGB')
w,h = im.size
im.crop((600, 100, w, 300)).resize((960, 400)).save('agent_memory/shots/real_top_crop.png')
