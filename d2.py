from PIL import Image
im=Image.open('_d.png').convert('RGB')
w,h=im.size
# thirds up
for nm,(a,b) in {'top':(0,0.45),'mid':(0.4,0.8),'bot':(0.75,1.0)}.items():
    c=im.crop((0,int(h*a),w,int(h*b)))
    c=c.resize((int(c.width*1.3),int(c.height*1.3)))
    c.save('_d_'+nm+'.png')
print('ok')
