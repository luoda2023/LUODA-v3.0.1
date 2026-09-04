from PIL import Image
im=Image.open('_r2.png').convert('RGB')
w,h=im.size
print('size',w,h)
im.resize((int(w*0.5),int(h*0.5))).save('_r2_small.png')
