from PIL import Image
im=Image.open('_win2.png').convert('RGB')
w,h=im.size
px=im.load()
samples=[px[x,y] for x in range(0,w,50) for y in range(0,h,50)]
nb=sum(1 for c in samples if sum(c)>60)
print('nonblack sample', nb, 'of', len(samples))
# save a downscaled preview + find window bbox via color diff
