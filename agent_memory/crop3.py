from PIL import Image
im = Image.open('agent_memory/shots/real_sent.png').convert('RGB')
w,h = im.size
im.resize((w//2, h//2)).save('agent_memory/shots/real_sent_half.png')
