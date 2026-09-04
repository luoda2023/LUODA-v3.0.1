from PIL import Image, ImageOps
im=Image.open('_r4.png').convert('L')
w,h=im.size
# full page 3x split contrast
for i,(a,b) in enumerate([(0,0.35),(0.32,0.7),(0.65,1.0)]):
    c=im.crop((0,int(h*a),w,int(h*b)))
    c=ImageOps.autocontrast(c)
    c=c.resize((int(c.width*1.5),int(c.height*1.5)))
    c.save(f'_r4_{i}.png')
print('ok')
