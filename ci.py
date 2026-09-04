from PIL import Image
im=Image.open('_inst_screen.png').convert('RGB')
w,h=im.size
print('size',w,h)
im.crop((0,int(h*0.85),w,h)).resize((int(w*1.0),int(h*0.15*1.4))).save('_inst_bottom.png')
print('saved')
