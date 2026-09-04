from PIL import Image
im=Image.open('_e2.png').convert('RGB')
w,h=im.size
# detailed top area 0-600
c=im.crop((0,100,w,700))
c=c.resize((int(c.width*1.2),int(c.height*1.2)))
c.save('_e2_top_detail.png')
# detailed 500-1300
c2=im.crop((0,450,w,1350))
c2=c2.resize((int(c2.width*1.2),int(c2.height*1.2)))
c2.save('_e2_mid_detail.png')
print('ok')
