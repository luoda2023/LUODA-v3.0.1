from PIL import Image
im=Image.open('_a.png').convert('RGB')
w,h=im.size
im.resize((int(w*0.55),int(h*0.55))).save('_a_small.png')
