from PIL import Image
im=Image.open('_ee.png').convert('RGB')
w,h=im.size
im.resize((int(w*0.6),int(h*0.6))).save('_ee_s.png')
print('ok')
