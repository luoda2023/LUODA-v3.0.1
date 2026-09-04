from PIL import Image
im=Image.open('_win_full.png').convert('RGB')
w,h=im.size
px=im.load()
# scan for non-black regions
def region_stats(x0,y0,x1,y1):
    import statistics
    samples=[px[x,y] for x in range(x0,x1,40) for y in range(y0,y1,40)]
    nonblack=sum(1 for c in samples if sum(c)>60)
    avg=tuple(sum(c[i] for c in samples)//len(samples) for i in range(3))
    return nonblack, avg
for name,(x0,y0,x1,y1) in {'window(599,117-1749,1037)':(599,117,1749,1037),'top-left':(0,0,600,400),'whole':(0,0,w,h)}.items():
    nb,avg=region_stats(x0,y0,x1,y1)
    print(name,'nonblack',nb,'avg',avg)
