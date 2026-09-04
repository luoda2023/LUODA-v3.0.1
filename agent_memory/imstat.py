from PIL import Image
from collections import Counter
import numpy as np
for p in ['agent_memory/logs/real_v2.png','agent_memory/logs/real_chat_again.png']:
    im = Image.open(p).convert('RGB')
    w,h = im.size
    a = np.array(im)
    # 亮度分布
    g = a.mean(axis=2)
    dark = (g<40).sum()
    bright = (g>200).sum()
    mid = (g>=40).sum() - bright
    total = g.size
    print(p, im.size, 'dark%%=%.1f bright%%=%.1f mid%%=%.1f' % (100*dark/total, 100*bright/total, 100*mid/total))
    c = Counter(im.getdata())
    print('   top:', c.most_common(3))
