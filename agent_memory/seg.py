from PIL import Image
import numpy as np
im = Image.open('agent_memory/shots/real_remote.png').convert('RGB')
a = np.array(im)
h,w,_ = a.shape
print('size', w, h)
for y0 in range(0, h, 200):
    seg = a[y0:min(y0+200,h)]
    # 平均色 + 非黑比例
    avg = seg.reshape(-1,3).mean(axis=0).round(0)
    dark = (seg.reshape(-1,3).sum(axis=1) < 90).mean()
    print(y0, 'avg', avg, 'dark%', round(100*dark,1))
