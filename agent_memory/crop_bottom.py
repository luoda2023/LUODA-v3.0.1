import io, sys
sys.stdout.reconfigure(encoding="utf-8")
try:
    from PIL import Image
except Exception as e:
    print("NO_PIL", e); sys.exit(0)
im = Image.open(r"agent_memory/shots/emu_remote.png")
print("size", im.size)
w, h = im.size
# 底部 40% 区域放大 1.5x 保存
crop = im.crop((0, int(h*0.5), w, h))
crop = crop.resize((int(crop.width*1.6), int(crop.height*1.6)))
crop.save(r"agent_memory/shots/emu_remote_bottom.png")
print("saved bottom")
