from PIL import Image
im=Image.open('_r7.png').convert('RGB')
w,h=im.size
# top area 0-300 full width
c=im.crop((0,0,w,320))
c=c.resize((int(c.width*1.3),int(c.height*1.3)))
c.save('_r7_tb.png')
print('ok')
