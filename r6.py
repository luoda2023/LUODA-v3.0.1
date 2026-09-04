from PIL import Image
im=Image.open('_r2.png').convert('RGB')
w,h=im.size
# grid view: split into 3x3 tiles, save each enlarged
for i in range(3):
    for j in range(3):
        x0=j*w//3; y0=i*h//3; x1=(j+1)*w//3; y1=(i+1)*h//3
        c=im.crop((x0,y0,x1,y1))
        c=c.resize((c.width*2,c.height*2))
        c.save(f'_r2_t{i}{j}.png')
print('ok')
