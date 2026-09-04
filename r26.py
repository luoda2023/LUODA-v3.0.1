from PIL import Image
im=Image.open('_r6.png').convert('RGB')
w,h=im.size
c=im.crop((0,int(h*0.86),w,h))
c=c.resize((int(c.width*1.6),int(c.height*1.6)))
c.save('_r6_nav.png')
print('ok')
