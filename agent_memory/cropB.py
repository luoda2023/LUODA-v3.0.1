from PIL import Image
im = Image.open('agent_memory/shots/real_remote.png').convert('RGB')
w,h = im.size
# 右上角 300x300 区域放大
im.crop((w-400, 0, w, 300)).resize((800, 600)).save('agent_memory/shots/real_topright.png')
