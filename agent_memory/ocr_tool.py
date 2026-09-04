import os, sys, subprocess
from rapidocr_onnxruntime import RapidOCR
ADB = r"J:\codex-work\.toolchains\android-sdk\platform-tools\adb.exe"
_ocr = RapidOCR()
def shot(dev, path):
    with open(path, 'wb') as f:
        subprocess.run([ADB, '-s', dev, 'exec-out', 'screencap', '-p'], stdout=f, check=True)
def ocr_img(path):
    result, _ = _ocr(path)
    out = []
    for line in (result or []):
        box, txt, conf = line[0], line[1], line[2]
        xs=[p[0] for p in box]; ys=[p[1] for p in box]
        cx=sum(xs)/4; cy=sum(ys)/4
        out.append({'text': txt, 'conf': round(float(conf),3), 'cx': round(cx), 'cy': round(cy),
                    'x0': int(min(xs)), 'y0': int(min(ys)), 'x1': int(max(xs)), 'y1': int(max(ys))})
    return out
def main():
    dev = sys.argv[1]; path = sys.argv[2]
    shot(dev, path)
    for it in ocr_img(path):
        print(f"{it['text']}\t{it['conf']}\t{it['cx']},{it['cy']}\t({it['x0']},{it['y0']})-({it['x1']},{it['y1']})")
if __name__=='__main__': main()
