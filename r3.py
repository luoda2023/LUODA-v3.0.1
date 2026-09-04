from PIL import Image
im=Image.open('_r2.png').convert('RGB')
w,h=im.size
c=im.crop((0,int(h*0.72),w,h))
c=c.resize((int(c.width*1.3),int(c.height*1.3)))
c.save('_r2_bot.png')
# also top
c2=im.crop((0,0,w,int(h*0.4)))
c2=c2.resize((int(c2.width*1.3),int(c2.height*1.3)))
c2.save('_r2_top.png')
print('ok')
