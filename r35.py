from PIL import Image
im=Image.open('_r7.png').convert('RGB')
w,h=im.size
c=im.resize((int(w*0.55),int(h*0.55)))
c.save('_r7_s.png')
print('ok')
