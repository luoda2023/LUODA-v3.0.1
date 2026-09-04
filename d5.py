from PIL import Image
im=Image.open('_d.png').convert('RGB')
w,h=im.size
# check if content is concentrated in a central card (white bg is around)
px=im.load()
# text density per row band: count non-background pixels
bg=(242,243,245)
for y0,y1 in [(0,400),(400,800),(800,1300),(1300,1800),(1800,2400)]:
    cnt=0; tot=0
    for y in range(y0,y1,2):
        for x in range(0,w,2):
            r,g,b=px[x,y]
            if abs(r-bg[0])+abs(g-bg[1])+abs(b-bg[2])>60:
                cnt+=1
            tot+=1
    print(y0,'-',y1,'nonbg%', round(cnt*100/tot,1))
