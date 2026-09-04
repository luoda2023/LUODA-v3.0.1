from PIL import Image
im = Image.open(r"agent_memory/shots/emu_remote.png")
w, h = im.size
crop = im.crop((0, 0, w, int(h*0.35)))
crop = crop.resize((int(crop.width*1.7), int(crop.height*1.7)))
crop.save(r"agent_memory/shots/emu_remote_top.png")
print("saved", crop.size)
