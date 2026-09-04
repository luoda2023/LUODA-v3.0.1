from PIL import Image
im=Image.open('_r6.png').convert('RGB')
w,h=im.size
c=im.crop((650,0,w,260))
c=c.resize((int(c.width*2.5),int(c.height*2.5)))
c.save('_r6_tr.png')
print('ok')
