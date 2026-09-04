from PIL import Image
im=Image.open('_e3.png').convert('RGB')
w,h=im.size
for nm,(a,b) in {'t':(0,0.35),'m':(0.3,0.75),'b':(0.7,1.0)}.items():
    c=im.crop((0,int(h*a),w,int(h*b)))
    c=c.resize((int(c.width*1.15),int(c.height*1.15)))
    c.save('_e3_'+nm+'.png')
print('ok',w,h)
