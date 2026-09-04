from PIL import Image
im=Image.open('_win_full.png').convert('RGB')
w,h=im.size
print('full',w,h)
# scale factor: full 2048x1280 desktop; window rect 599,117-1749,1037 => assume same coord system
crop=im.crop((599,117,1749,1037))
crop=crop.resize((crop.width//1, crop.height//1))
crop.save('_win_crop.png')
print('crop', crop.size)
