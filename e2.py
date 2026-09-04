from PIL import Image
im=Image.open('_e2.png').convert('RGB')
w,h=im.size
print('size',w,h)
for nm,(a,b) in {'t':(0,0.33),'m':(0.3,0.72),'b':(0.68,1.0)}.items():
    c=im.crop((0,int(h*a),w,int(h*b)))
    c=c.resize((int(c.width*1.1),int(c.height*1.1)))
    c.save('_e2_'+nm+'.png')
