from PIL import Image
im = Image.open('agent_memory/shots/real_top.png').convert('RGB')
w,h = im.size
# 右端 400px 全高预览顶部300
im.crop((680, 100, w, 300)).resize((800, 400)).save('agent_memory/shots/real_icons.png')
