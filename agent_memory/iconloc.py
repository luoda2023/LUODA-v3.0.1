from PIL import Image
import numpy as np
im = Image.open('agent_memory/shots/real_top.png').convert('RGB')
a = np.array(im)
# 分析顶部区域找图标(非白非背景像素簇)
# 顶部区域 y 100-280
seg = a[100:280, 600:1080]
# 找深色/绿色像素(图标)
for x0 in range(600, 1080, 20):
    col = a[100:280, x0:x0+20]
    # 非白像素数(图标墨水)
    nonwhite = ((col.sum(axis=2) < 600)).mean()
    if nonwhite > 0.05:
        print('x', x0, 'ink%', round(100*nonwhite,1))
