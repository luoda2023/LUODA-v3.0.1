from PIL import Image
for f,out in [('_real_v324.png','_real_v324_s.png'),('_emu_v324.png','_emu_v324_s.png')]:
    im=Image.open(f).convert('RGB')
    w,h=im.size
    # top third
    im.crop((0,0,w,int(h*0.33))).resize((int(w*0.9),int(h*0.33*0.9))).save('_t_'+out)
    # middle third
    im.crop((0,int(h*0.30),w,int(h*0.70))).resize((int(w*0.9),int(h*0.4*0.9))).save('_m_'+out)
    # bottom
    im.crop((0,int(h*0.66),w,h)).resize((int(w*0.9),int(h*0.34*0.9))).save('_b_'+out)
print('ok')
