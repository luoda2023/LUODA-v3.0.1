from PIL import Image
im = Image.open('agent_memory/shots/real_remote.png').convert('RGB')
w,h = im.size
# 保存左边缘和底部区域用于查看工具条细节
im.crop((0, 100, w, 500)).save('agent_memory/shots/real_remote_mid.png')
