from PIL import Image, ImageOps
im=Image.open('_r5.png').convert('RGB')
w,h=im.size
# Save the FULL page color (not gray) downscaled to 720 wide
c=im.resize((720, int(720*h/w)))
c.save('_r5_full.png')
print('ok')
