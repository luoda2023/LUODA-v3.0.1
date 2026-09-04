from PIL import Image
im=Image.open('_a.png').convert('RGB')
w,h=im.size
px=im.load()
# dark text detection in central dialog card - sample rows 500-1500 for dark pixel runs (text lines)
for y in range(500,1600,30):
    dark=0
    for x in range(60,1021,4):
        r,g,b=px[x,y]
        if r<100 and g<100 and b<100: dark+=1
    if dark>3: print('textrow',y,'dark',dark)
