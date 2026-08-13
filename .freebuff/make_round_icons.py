#!/usr/bin/env python3
"""生成圆形版本的应用图标（透明背景 + 圆形绿色底 + 白色对话图案）。

微信风格：无论 launcher 用圆形还是圆角方形 mask，图标都显示为圆形。
"""
from PIL import Image, ImageDraw, ImageOps
import os, shutil

ROOT = 'J:/codex-work/LUODA-v3.0.1/flutter'
SRC = os.path.join(ROOT, 'assets', 'icon.png')
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')

SIZES = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}

# adaptive icon foreground/monochrome 用更大的画布（108dp 对应密度）
ADAPTIVE_SIZES = {
    'mipmap-mdpi': 108,
    'mipmap-hdpi': 162,
    'mipmap-xhdpi': 216,
    'mipmap-xxhdpi': 324,
    'mipmap-xxxhdpi': 432,
}

src = Image.open(SRC).convert('RGBA')
sw, sh = src.size

# ---- 提取白色图案（monochrome：白底上取非绿色内容）----
def extract_pattern(img, size):
    """从品牌图标提取白色图案区域（保留白色，其他透明）。"""
    img = img.resize((size, size), Image.LANCZOS)
    px = img.load()
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    opx = out.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = px[x, y]
            if a < 60:
                continue
            # 白色 = 图案
            if r > 200 and g > 200 and b > 200:
                opx[x, y] = (255, 255, 255, 255)
            # 接近白色的浅绿也保留
            elif r > 180 and g > 200 and b > 180:
                opx[x, y] = (255, 255, 255, 255)
    return out

def round_mask(size, radius_ratio=0.5):
    """圆形 mask（全幅圆形）。"""
    mask = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse([0, 0, size - 1, size - 1], fill=255)
    return mask

def make_circle_icon(size):
    """圆形品牌图标：透明背景 + 圆形绿色+白色图案。"""
    img = src.resize((size, size), Image.LANCZOS)
    mask = round_mask(size)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out

def make_adaptive_foreground(size):
    """adaptive icon 前景：透明背景 + 圆形绿色底（占满）+ 白色图案（中心安全区）。
    圆形绿色直径 = size（满幅），图案在中心 60% 区域。"""
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    # 圆形绿色底
    g = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(g)
    d.ellipse([0, 0, size - 1, size - 1], fill=(84, 188, 103, 255))
    canvas = Image.alpha_composite(canvas, g)
    # 白色图案（从品牌图标提取，缩放到安全区 66%）
    pat = extract_pattern(src, int(size * 0.72))
    pat = pat.resize((int(size * 0.72), int(size * 0.72)), Image.LANCZOS)
    off = (size - pat.width) // 2
    canvas.alpha_composite(pat, (off, off))
    return canvas

def make_monochrome(size):
    """monochrome：透明背景 + 白色图案（中心 66%）。"""
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    pat = extract_pattern(src, int(size * 0.66))
    pat = pat.resize((int(size * 0.66), int(size * 0.66)), Image.LANCZOS)
    off = (size - pat.width) // 2
    canvas.alpha_composite(pat, (off, off))
    return canvas

# 备份旧文件
backup_dir = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res', '.icon_backup')
if not os.path.exists(backup_dir):
    os.makedirs(backup_dir)
    for d, _ in SIZES.items():
        src_dir = os.path.join(RES, d)
        dst_dir = os.path.join(backup_dir, d)
        if os.path.isdir(src_dir):
            shutil.copytree(src_dir, dst_dir, dirs_exist_ok=True)
    print('已备份原图标到', backup_dir)

for d, size in SIZES.items():
    out_dir = os.path.join(RES, d)
    # legacy ic_launcher.png / ic_launcher_round.png：圆形
    make_circle_icon(size).save(os.path.join(out_dir, 'ic_launcher.png'))
    make_circle_icon(size).save(os.path.join(out_dir, 'ic_launcher_round.png'))
    print(f'{d}: ic_launcher.png {size}x{size} OK')

for d, size in ADAPTIVE_SIZES.items():
    out_dir = os.path.join(RES, d)
    make_adaptive_foreground(size).save(os.path.join(out_dir, 'ic_launcher_foreground.png'))
    make_monochrome(size).save(os.path.join(out_dir, 'ic_launcher_monochrome.png'))
    print(f'{d}: foreground/monochrome {size}x{size} OK')

# background 改成透明（圆形由 foreground 承载）
bg_path = os.path.join(RES, 'values', 'ic_launcher_background.xml')
with open(bg_path, 'w', encoding='utf-8') as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#00000000</color>\n</resources>\n')
print('ic_launcher_background -> transparent OK')

# 验证生成结果
v = Image.open(os.path.join(RES, 'mipmap-xxxhdpi', 'ic_launcher_foreground.png'))
print('验证 foreground:', v.size, '角落像素:', v.getpixel((0, 0)), '中心像素:', v.getpixel((216, 216)))
v2 = Image.open(os.path.join(RES, 'mipmap-xxxhdpi', 'ic_launcher.png'))
print('验证 legacy:', v2.size, '角落像素:', v2.getpixel((0, 0)))
print('ALL DONE')
