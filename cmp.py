from PIL import Image
import collections
for f in ['_r3.png','_r2.png','_e2.png','_e3.png']:
    im=Image.open(f).convert('RGB')
    w,h=im.size
    px=im.load()
    cnt=collections.Counter()
    for y in range(0,h,15):
        for x in range(0,w,15):
            r,g,b=px[x,y]
            cnt[(r//50*50,g//50*50,b//50*50)]+=1
    print(f, im.size, 'top colors:')
    for c,n in cnt.most_common(4):
        print('   ',c,n)
