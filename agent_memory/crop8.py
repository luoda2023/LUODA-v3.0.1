from PIL import Image
im = Image.open('agent_memory/shots/real_remote.png').convert('RGB')
w,h = im.size
# 顶部工具栏区域
im.crop((0, 0, w, 300)).resize((w, 600)).save('agent_memory/shots/real_remote_toolbar.png')
