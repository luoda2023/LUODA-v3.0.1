from PIL import Image
im=Image.open('_r3.png').convert('RGB')
w,h=im.size
im.resize((int(w*0.55),int(h*0.55))).save('_r3_s.png')
print('ok')
