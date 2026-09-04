from PIL import Image
im=Image.open('_r7.png').convert('RGB')
w,h=im.size
# 3 bands
for nm,(a,b) in {'top':(0,0.35),'mid':(0.3,0.75),'bot':(0.7,1.0)}.items():
    c=im.crop((0,int(h*a),w,int(h*b)))
    c=c.resize((int(c.width*1.4),int(c.height*1.4)))
    c.save('_r7_'+nm+'.png')
print('ok')
