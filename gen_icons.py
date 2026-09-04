from PIL import Image, ImageDraw, ImageOps
import os

src = Image.open("Images/Botchat-new.png").convert("RGBA")
print("src size", src.size, "bbox", src.getbbox())

# crop transparent padding
bbox = src.getbbox()
content = src.crop(bbox)

res_dir = "flutter/android/app/src/main/res"
sizes = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

def fit_square(img, size, pad_ratio):
    # scale content to (size * (1-pad)) while keeping aspect, center
    target = int(size * (1 - pad_ratio))
    img2 = img.copy()
    img2.thumbnail((target, target), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0,0,0,0))
    ox = (size - img2.width)//2
    oy = (size - img2.height)//2
    canvas.paste(img2, (ox, oy), img2)
    return canvas

for name, size in sizes.items():
    d = os.path.join(res_dir, "mipmap-"+name)
    os.makedirs(d, exist_ok=True)
    # legacy launcher: fill almost full (tiny pad so launcher mask does not cut)
    leg = fit_square(content, size, 0.06)
    leg.save(os.path.join(d, "ic_launcher.png"))
    leg.save(os.path.join(d, "ic_launcher_round.png"))
    leg.save(os.path.join(d, "ic_stat_logo.png"))
    # adaptive foreground: content occupies ~62% safe zone
    fg = fit_square(content, 432, 0.38)
    fg.save(os.path.join(d, "ic_launcher_foreground.png"))
    # monochrome: alpha mask tinted white
    alpha = content.split()[3]
    mono = Image.new("RGBA", content.size, (255,255,255,0))
    mono.putalpha(alpha)
    mono = fit_square(mono, 432, 0.38)
    mono.save(os.path.join(d, "ic_launcher_monochrome.png"))
    print("done", name, size)

print("ALL OK")
