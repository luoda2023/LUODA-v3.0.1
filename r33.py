from PIL import Image
import numpy as np
im=Image.open('_r6.png').convert('RGB')
a=np.asarray(im)
# top bar likely y0-140; find white icons on green bg in y40-130
crop=a[30:140, :, :]
# green header color ~ (150-230, 200-250, 190-240)? detect dominant
sub=crop[::3,::3].reshape(-1,3)
from collections import Counter
top=Counter(map(tuple,sub)).most_common(3)
print('top colors y30-140:', top)
