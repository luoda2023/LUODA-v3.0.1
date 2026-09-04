from PIL import Image
im=Image.open('_now.png').convert('RGB')
w,h=im.size
# middle band (dialog content) full-width view
im.resize((540,1200)).save('_now_small.png')
# upper area where dialog body may be
