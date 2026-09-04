from PIL import Image
im=Image.open('_win_crop.png').convert('RGB')
w,h=im.size
# lower half area (chat input likely near bottom), upscale 1.5x and save segments
seg=im.crop((0,int(h*0.55),w,h))
seg=seg.resize((int(seg.width*1.6), int(seg.height*1.6)))
seg.save('_win_bottom.png')
print('saved bottom', seg.size)
