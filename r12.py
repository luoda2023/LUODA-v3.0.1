from PIL import Image
im=Image.open('_r3.png').convert('RGB')
w,h=im.size
c=im.crop((0,0,w,550))
c=c.resize((c.width*2,c.height*2))
c.save('_r3_h2.png')
print('ok')
