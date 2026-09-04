from PIL import Image
im=Image.open('_r3.png').convert('RGB')
w,h=im.size
print(w,h)
for nm,(a,b) in {'top':(0,0.4),'mid':(0.35,0.8),'bot':(0.75,1.0)}.items():
    c=im.crop((0,int(h*a),w,int(h*b)))
    c=c.resize((int(c.width*1.4),int(c.height*1.4)))
    c.save('_r3_'+nm+'.png')
