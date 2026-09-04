from PIL import Image
im=Image.open('_d.png').convert('RGB')
w,h=im.size
px=im.load()
# rows avg brightness
for y in range(0,h,120):
    row=[px[x,y] for x in range(0,w,80)]
    avg=tuple(sum(c[i] for c in row)//len(row) for i in range(3))
    print(y, avg)
