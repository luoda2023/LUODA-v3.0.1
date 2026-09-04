from PIL import Image
im=Image.open('_m1.png').convert('RGB')
w,h=im.size
c=im.crop((600,0,w,700))
c=c.resize((int(c.width*1.3),int(c.height*1.3)))
c.save('_m1_menu.png')
print('ok')
