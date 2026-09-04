from PIL import Image
im = Image.open('agent_memory/shots/real_chat2.png').convert('RGB')
w,h = im.size
# 分成两半保存便于查看
im.crop((0, 0, w, h//2)).save('agent_memory/shots/real_chat2_top.png')
