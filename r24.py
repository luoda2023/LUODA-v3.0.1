from PIL import Image
im=Image.open('_r6.png').convert('RGB')
w,h=im.size
c=im.resize((int(w*0.6),int(h*0.6)))
c.save('_r6_s.png')
# three bands
for nm,(a,b) in {'t':(0,0.4),'m':(0.35,0.8),'b':(0.72,1.0)}.items():
    cc=im.crop((0,int(h*a),w,int(h*b)))
    cc.save(f'_r6_{nm}.png')
print('ok')
