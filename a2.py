from PIL import Image
im=Image.open('_a.png').convert('RGB')
w,h=im.size
# middle region full detail
c=im.crop((0,int(h*0.15),w,int(h*0.75)))
c=c.resize((int(c.width*1.5),int(c.height*1.5)))
c.save('_a_mid.png')
print('ok', c.size)
