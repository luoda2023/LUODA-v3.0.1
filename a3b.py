from PIL import Image
im=Image.open('_a2.png').convert('RGB')
w,h=im.size
# 3 bands detail
for nm,(a,b) in {'top':(0,0.3),'mid':(0.25,0.7),'bot':(0.6,1.0)}.items():
    c=im.crop((0,int(h*a),w,int(h*b)))
    c=c.resize((int(c.width*1.4),int(c.height*1.4)))
    c.save('_a2_'+nm+'.png')
print('ok')
