from PIL import Image
im=Image.open('_r6.png').convert('RGB')
w,h=im.size
c=im.crop((0,0,w,500))
c=c.resize((int(c.width*1.5),int(c.height*1.5)))
c.save('_r6_top.png')
print('ok')
