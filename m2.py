from PIL import Image
im=Image.open('_m1.png').convert('RGB')
w,h=im.size
im.resize((int(w*0.6),int(h*0.6))).save('_m1_s.png')
# focus menu area top right
c=im.crop((500,100,w,900))
c=c.resize((int(c.width*1.6),int(c.height*1.6)))
c.save('_m1_zoom.png')
print('ok')
