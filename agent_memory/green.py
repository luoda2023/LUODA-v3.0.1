from PIL import Image
import numpy as np
im = Image.open('agent_memory/shots/real_remote.png').convert('RGB')
a = np.array(im)
w,h,_ = a.shape
# 找绿色 (greenAccent ~ (0,255,0)偏亮绿) 像素
mask = (a[:,:,1] > 150) & (a[:,:,0] < 150) & (a[:,:,2] < 150)
ys, xs = np.where(mask)
if len(xs):
    print('green bbox:', xs.min(), ys.min(), xs.max(), ys.max(), 'count', len(xs))
else:
    print('no green pixels')
# 顶部200px 区域颜色分布
top = a[0:250]
for y0 in range(0,250,50):
    seg = top[y0:y0+50]
    # 平均色
    print(y0, 'avg', seg.reshape(-1,3).mean(axis=0).round(1))
