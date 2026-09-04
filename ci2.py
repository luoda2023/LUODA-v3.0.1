from PIL import Image
im=Image.open('_inst_screen.png').convert('RGB')
w,h=im.size
print('size',w,h)
im.save('_inst_view.png')
# bottom band
b=im.crop((0,int(h*0.8),w,h)); b=b.resize((int(b.width*1.2),int(b.height*1.2))); b.save('_inst_bottom.png')
print('ok')
