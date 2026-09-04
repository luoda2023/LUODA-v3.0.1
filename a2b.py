from PIL import Image
im=Image.open('_a2.png').convert('RGB')
w,h=im.size
im.resize((int(w*0.6),int(h*0.6))).save('_a2_s.png')
print('ok')
