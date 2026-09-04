from PIL import Image
im=Image.open('_win_crop.png').convert('RGB')
w,h=im.size
# Detect layout: sample colors at grid positions to find conversation list & chat area
px=im.load()
for y in [100,300,500,700,880]:
    row=[]
    for x in [50,150,250,350,500,700,900,1100]:
        row.append(str(px[x,y]))
    print(y, row)
