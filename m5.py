from PIL import Image
im=Image.open('_m1.png').convert('RGB')
w,h=im.size
# menu panel area x540-840 y230-1000 enlarged 2x
c=im.crop((540,230,860,1010))
c=c.resize((c.width*2,c.height*2))
c.save('_m1_items.png')
print('ok')
